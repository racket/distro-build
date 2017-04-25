#lang racket/base
(require racket/cmdline
         racket/string
         (only-in "config.rkt" extract-options))

(module test racket/base)

(define-values (config-file config-mode default-pkgs flags)
  (command-line
   #:args
   (config-file config-mode pkgs . flag)
   (values config-file config-mode pkgs flag)))

(define config (extract-options config-file config-mode))

(define pkgs (append (or (hash-ref config '#:pkgs #f)
                         (string-split default-pkgs))
                     (hash-ref config '#:test-pkgs '())))

(parameterize ([current-command-line-arguments
                (list->vector (append (list "pkg" "install")
                                      flags
                                      pkgs))])
  (dynamic-require 'raco #f))
