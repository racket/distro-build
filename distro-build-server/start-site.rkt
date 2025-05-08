#lang racket/base
(require racket/cmdline
         racket/string
         (only-in "config.rkt"
                  current-mode
                  site-config-options))

(module test racket/base)

(define-values (config-file config-mode)
  (command-line
   #:args
   (config-file config-mode)
   (values config-file config-mode)))

(define c
  (parameterize ([current-mode config-mode])
    (dynamic-require (path->complete-path config-file) 'site-config)))

(define config (site-config-options c))

((hash-ref config '#:start-hook (lambda () void)) c)
