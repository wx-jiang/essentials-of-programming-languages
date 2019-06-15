#lang eopl

(define empty-env
  (lambda ()
    (lambda (search-var)
      (report-no-binding-found search-var))))

(define extend-env
  (lambda (saved-var saved-val saved-env)
    (lambda (search-var)
      (if (eqv? search-var saved-var)
          saved-val
          (apply-env saved-env search-var)))))

(define apply-env
  (lambda (env search-var)
    (env search-var)))

(define report-no-binding-found
  (lambda (search-var)
    (eopl:error 'apply-env "no binding for: ~s" search-var)))

(define init-env
  (lambda ()
    (extend-env 'i (num-val 1)
                (extend-env 'j (num-val 2)
                            (extend-env 'k (num-val 0)
                                        (empty-env))))))

(define identifier?
  (lambda (x)
    (and (symbol? x)
         (not (eqv? x 'lambda))
         (not (eqv? x 'define)))))

(define-datatype program program?
  [a-program (exp1 expression?)])

(define-datatype expression expression?
  [const-exp (exp1 number?)]
  [var-exp (var identifier?)]
  [equal?-exp (exp1 expression?)
              (exp2 expression?)]
  [greater?-exp (exp1 expression?)
                (exp2 expression?)]
  [less?-exp (exp1 expression?)
             (exp2 expression?)]
  [diff-exp (exp1 expression?)
            (exp2 expression?)]
  [minus-exp (exp1 expression?)]
  [add-exp (exp1 expression?)
           (exp2 expression?)]
  [multi-exp (exp1 expression?)
             (exp2 expression?)]
  [quotient-exp (exp1 expression?)
                (exp2 expression?)]
  [zero?-exp (exp1 expression?)]
  [if-exp (exp1 expression?)
          (exp2 expression?)
          (exp3 expression?)]
  [let-exp (var identifier?)
           (exp1 expression?)
           (body expression?)])

(define lex-let
  '((whitespace (whitespace) skip)
    (commit ("%" (arbno (not #\newline))) skip)
    (identifier (letter (arbno (or letter digit))) symbol)
    (number (digit (arbno digit)) number)))

(define grammar-let
  '((program (expression) a-program)
    (expression (number) const-exp)
    (expression (identifier) var-exp)
    (expression ("equal?" "(" expression "," expression ")") equal?-exp)
    (expression ("greater?" "(" expression "," expression ")") greater?-exp)
    (expression ("less?" "(" expression "," expression ")") less?-exp)
    (expression ("minus" "(" expression ")") minus-exp)
    (expression ("-" "(" expression "," expression ")") diff-exp)
    (expression ("+" "(" expression "," expression ")") add-exp)
    (expression ("*" "(" expression "," expression ")") multi-exp)
    (expression ("/" "(" expression "," expression ")") quotient-exp)
    (expression ("zero?" "(" expression ")") zero?-exp)
    (expression ("if" expression "then" expression "else" expression) if-exp)
    (expression ("let" identifier "=" expression "in" expression) let-exp)))

(define scan&parse
  (sllgen:make-string-parser lex-let grammar-let))

(define-datatype expval expval?
  [num-val (num number?)]
  [bool-val (bool boolean?)])

(define expval->num
  (lambda (val)
    (cases expval val
      (num-val (num) num)
      (else (report-expval-extractor-error 'num val)))))

(define expval->bool
  (lambda (val)
    (cases expval val
      (bool-val (bool) bool)
      (else (report-expval-extractor-error 'bool val)))))

(define report-expval-extractor-error
  (lambda (type val)
    (eopl:error "expval's extractor is not suit the exp: ~s" val)))

(define run
  (lambda (string)
    (value-of-program (scan&parse string))))

(define value-of-program
  (lambda (pgm)
    (cases program pgm
      (a-program (exp1)
                 (value-of exp1 (init-env))))))

(define value-of
  (lambda (exp env)
    (cases expression exp
      (const-exp (num) (num-val num))
      (var-exp (var) (apply-env env var))
      (equal?-exp (exp1 exp2)
                  (let ([val1 (value-of exp1 env)]
                        [val2 (value-of exp2 env)])
                    (let ([num1 (expval->num val1)]
                          [num2 (expval->num val2)])
                      (if (eq? num1 num2)
                          (bool-val #t)
                          (bool-val #f)))))
      (greater?-exp (exp1 exp2)
                    (let ([val1 (value-of exp1 env)]
                          [val2 (value-of exp2 env)])
                      (let ([num1 (expval->num val1)]
                            [num2 (expval->num val2)])
                        (if (> num1 num2)
                            (bool-val #t)
                            (bool-val #f)))))
      (less?-exp (exp1 exp2)
                 (let ([val1 (value-of exp1 env)]
                       [val2 (value-of exp2 env)])
                   (let ([num1 (expval->num val1)]
                         [num2 (expval->num val2)])
                     (if (< num1 num2)
                         (bool-val #t)
                         (bool-val #f)))))
      (minus-exp (num) (num-val (- (expval->num (value-of num env)))))
      (add-exp (exp1 exp2)
               (let ([val1 (value-of exp1 env)]
                     [val2 (value-of exp2 env)])
                 (let ([num1 (expval->num val1)]
                       [num2 (expval->num val2)])
                   (num-val (+ num1 num2)))))
      (diff-exp (exp1 exp2)
                (let ([val1 (value-of exp1 env)]
                      [val2 (value-of exp2 env)])
                  (let ([num1 (expval->num val1)]
                        [num2 (expval->num val2)])
                    (num-val (- num1 num2)))))
      (multi-exp (exp1 exp2)
                 (let ([val1 (value-of exp1 env)]
                       [val2 (value-of exp2 env)])
                   (let ([num1 (expval->num val1)]
                         [num2 (expval->num val2)])
                     (num-val (* num1 num2)))))
      (quotient-exp (exp1 exp2)
                    (let ([val1 (value-of exp1 env)]
                          [val2 (value-of exp2 env)])
                      (let ([num1 (expval->num val1)]
                            [num2 (expval->num val2)])
                        (num-val (quotient num1 num2)))))
      (zero?-exp (exp1)
                 (let ([val1 (value-of exp1 env)])
                   (let ([num1 (expval->num val1)])
                     (if (zero? num1)
                         (bool-val #t)
                         (bool-val #f)))))
      (if-exp (exp1 exp2 exp3)
              (let ([val1 (value-of exp1 env)])
                (if (expval->bool val1)
                    (value-of exp2 env)
                    (value-of exp3 env))))
      (let-exp (id exp1 body)
               (let ([val1 (value-of exp1 env)])
                 (value-of body (extend-env id val1 env)))))))
 
(define s1 "+(i, minus(j))")
(define s2 "let x = 0 in if zero?(0) then minus(8) else minus(i)")
(define s3 "let a = 9 in let b = 10 in if greater?(a, b) then *(a, b) else -(a, b)") 

(display (run s1))
(newline)
(display (run s2))
(newline)
(display (run s3))