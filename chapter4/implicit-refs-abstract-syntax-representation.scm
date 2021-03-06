#lang eopl

(define list-of
  (lambda (pred)
    (lambda (x)
      (or (null? x)
          (and (pair? x)
               (pred (car x))
               ((list-of pred) (cdr x)))))))

; parser
(define the-lexical-spec
  '((whitespace (whitespace) skip)
    (comment ("%" (arbno (not #\newline))) skip)
    (identifier (letter (arbno (or letter digit "_" "-" "?"))) symbol)
    (number (digit (arbno digit)) number)
    (number ("-" digit (arbno digit)) number)))

(define the-grammar
  '((program (expression) a-program)
    (expression (number) const-exp)
    (expression ("-" "(" expression "," expression ")") diff-exp)
    (expression ("zero?" "(" expression ")") zero?-exp)
    (expression ("if" expression "then" expression "else" expression) if-exp)
    (expression (identifier) var-exp)
    (expression ("let" identifier "=" expression "in" expression) let-exp)
    (expression ("proc" "(" identifier ")" expression) proc-exp)
    (expression ("(" expression expression ")") call-exp)
    (expression ("letrec" (arbno identifier "(" identifier ")" "=" expression) "in" expression) letrec-exp)
    (expression ("begin" expression (arbno ";" expression) "end") begin-exp)
    (expression ("set" identifier "=" expression) assign-exp)))

(sllgen:make-define-datatypes the-lexical-spec the-grammar)

(define show-the-datatypes
  (lambda () (sllgen:list-define-datatypes the-lexical-spec the-grammar)))

(define scan&parse
  (sllgen:make-string-parser the-lexical-spec the-grammar))

; data type
(define-datatype expval expval?
  (num-val
   (number number?))
  (bool-val
   (bool boolean?))
  (proc-val
   (proc proc?))
  (ref-val
   (ref reference?)))

(define expval->num
  (lambda (v)
    (cases expval v
           (num-val (num) num)
           (else (expval-extractor-error 'num v)))))

(define expval->bool
  (lambda (v)
    (cases expval v
           (bool-val (bool) bool)
           (else (expval-extractor-error 'bool v)))))

(define expval->proc
  (lambda (v)
    (cases expval v
           (proc-val (proc) proc)
           (else (expval-extractor-error 'proc v)))))

(define expval->ref
  (lambda (v)
    (cases expval v
      (ref-val (ref) ref)
      (else (expval-extractor-error 'reference v)))))

(define expval-extractor-error
  (lambda (variant value)
    (eopl:error 'expval-extractors "Looking for a ~s, found ~s"
                variant value)))

(define-datatype proc proc?
  (procedure
   (bvar symbol?)
   (body expression?)
   (env environment?)))

; environment
(define-datatype environment environment?
  (empty-env)
  (extend-env
   (bvar symbol?)
   (bval reference?)
   (saved-env environment?))
  (extend-env-rec
   (proc-names (list-of symbol?))
   (b-vars (list-of symbol?))
   (proc-bodies (list-of expression?))
   (saved-env environment?)))

(define apply-env
  (lambda (env search-var)
    (cases environment env
      (empty-env ()
                 (report-no-binding-found search-var))
      (extend-env (saved-var saved-val saved-env)
                  (if (eqv? saved-var search-var)
                      saved-val
                      (apply-env saved-env search-var)))
      (extend-env-rec (p-names b-vars p-bodys saved-env)
                      (let ((n (location search-var p-names)))
                        (let ((len (length p-names)))
                          (if (< n len)
                              (newref (proc-val (procedure (list-ref b-vars n)
                                                           (list-ref p-bodys n)
                                                           env)))
                              (apply-env saved-env search-var))))))))

(define location
  (lambda (search-var p-names)
    (cond ((null? p-names)
           1)
          ((eqv? (car p-names) search-var)
           0)
          (else
           (+ 1 (location search-var (cdr p-names)))))))

(define report-no-binding-found
  (lambda (search-var)
    (eopl:error "there is not ~s in environment" search-var)))

; store
(define empty-store
  (lambda () '()))

(define the-store 'uninitialized)

(define get-store
  (lambda () the-store))

(define initialize-store!
  (lambda ()
    (set! the-store (empty-store))))

(define reference?
  (lambda (v)
    (integer? v)))

(define newref
  (lambda (val)
    (let ((next-ref (length the-store)))
      (set! the-store (append the-store (list val)))
      next-ref)))

(define deref
  (lambda (ref)
    (list-ref the-store ref)))

(define setref!
  (lambda (ref val)
    (set! the-store
          (letrec ((setref-inner
                    (lambda (store1 ref1)
                      (cond ((null? store1)
                             (report-invalid-reference ref))
                            ((zero? ref1)
                             (cons val (cdr store1)))
                            (else
                             (cons (car store1)
                                   (setref-inner (cdr store1) (- ref1 1))))))))
            (setref-inner the-store ref)))))

(define report-invalid-reference
  (lambda (ref)
    (eopl:error "there isn't ~s" ref)))

; run and deal with the AST
(define init-env
  (lambda ()
    (empty-env)))

(define apply-procedure
  (lambda (proc1 arg)
    (cases proc proc1
      (procedure (var body saved-env)
                 (value-of body
                           (extend-env var (newref arg) saved-env))))))

(define run
  (lambda (string)
    (value-of-program (scan&parse string))))

(define value-of-program
  (lambda (pgm)
    (initialize-store!)
    (cases program pgm
      (a-program (exp1)
                 (value-of exp1 (init-env))))))

(define value-of
  (lambda (exp env)
    (cases expression exp
      (const-exp (num)
                 (num-val num))
      (var-exp (var)
               (deref (apply-env env var)))  
      (diff-exp (exp1 exp2)
                (let ((num1 (expval->num (value-of exp1 env)))
                      (num2 (expval->num (value-of exp2 env))))
                  (num-val (- num1 num2))))
      (zero?-exp (exp1)
                 (let ((num1 (expval->num (value-of exp1 env))))
                   (if (zero? num1)
                       (bool-val #t)
                       (bool-val #f))))
      (if-exp (exp1 exp2 exp3)
              (let ((bool1 (expval->bool (value-of exp1 env))))
                (if bool1
                    (value-of exp2 env)
                    (value-of exp3 env))))
      (let-exp (var exp1 body)
               (let ((val1 (newref (value-of exp1 env))))
                 (value-of body (extend-env var val1 env))))
      (proc-exp (var body)
                (proc-val (procedure var body env)))
      (call-exp (rator rand)
                (let ((proc (expval->proc (value-of rator env)))
                      (arg (value-of rand env)))
                  (apply-procedure proc arg)))
      (letrec-exp (p-names b-vars p-bodies letrec-body)
                  (value-of letrec-body
                            (extend-env-rec p-names b-vars p-bodies env)))
      (begin-exp (exp1 exps)
                 (letrec ((value-of-begins
                           (lambda (e1 es)
                             (let ((v1 (value-of e1 env)))
                               (if (null? es)
                                   v1
                                   (value-of-begins (car es) (cdr es)))))))
                   (value-of-begins exp1 exps)))
      (assign-exp (var exp1)
                  (begin
                    (setref! (apply-env env var)
                             (value-of exp1 env))
                    (num-val 27))))))


(define l1 "let x = 0
                in letrec even(dummy) = if zero?(x)
                                        then 1
                                        else begin
                                             set x = -(x,1);
                                             (odd 888)
                                             end
                          odd(dummy) = if zero?(x)
                                       then 0
                                       else begin
                                            set x = -(x,1);
                                            (even 888)
                                            end
                          in begin
                             set x = 12;
                             (odd -888)
                             end")

(define l2 "let g = let count = 0
                        in proc (dummy)
                                begin
                                set count = -(count,-1);
                                count
                                end
                in let a = (g 11)
                       in let b = (g 11)
                              in -(a,b)")

(display (run l1))
(newline)
(display (run l2))