#lang racket/base
(require setup/cross-system)

(provide target-machine-flags)

;; Infer flags to pass to another Racket process:
(define (target-machine-flags)
  (append
   (if (not (current-compile-target-machine))
       '("-M")
       null)
   (if (cross-installation?)
       '("-C")
       null)
   (let ([l (current-compiled-file-roots)])
     (cond
       [(null? l)
        ;; Can't really propagate an empty list!
        null]
       [(and (= (length l) 1)
             (or (eq? 'same (car l))
                 (equal? (build-path 'same) (car l))))
        null]
       [else
        (define (path->path-list-string p)
          (cond
            [(eq? p 'same) "."]
            [else (path->string p)]))
        (list
         "-R"
         (let loop ([l l])
           (cond
             [(null? (cdr l))
              (path->path-list-string (car l))]
             [else
              (string-append (path->path-list-string (car l))
                             ":"
                             (loop (cdr l)))])))]))))

