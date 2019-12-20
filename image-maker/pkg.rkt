#lang racket/base
(require (only-in pict scale-color)
         racket/draw
         racket/class)

(provide draw-pkg)

(define box-base
  (let ([p (new dc-path%)])
    (send p move-to 80 80)
    (send p line-to 50 100)
    (send p line-to 20 80)
    (send p line-to 20 40)
    (send p line-to 50 60)
    (send p line-to 80 40)
    (send p close)
    p))

(define box-inside
  (let ([p (new dc-path%)])
    (send p move-to 20 40)
    (send p line-to 50 60)
    (send p line-to 80 40)
    (send p line-to 50 25)
    (send p close)
    p))

(define box-back-arms
  (let ([p (new dc-path%)])
    (send p move-to 20 40)
    (send p line-to 5 25)
    (send p line-to 35 10)
    (send p line-to 50 25)
    (send p close)
    (send p move-to 80 40)
    (send p line-to 95 25)
    (send p line-to 65 10)
    (send p line-to 50 25)
    (send p close)
    p))

(define box-front-arms
  (let ([p (new dc-path%)])
    (send p move-to 20 40)
    (send p line-to 5 55)
    (send p line-to 35 75)
    (send p line-to 50 60)
    (send p close)
    (send p move-to 80 40)
    (send p line-to 95 55)
    (send p line-to 65 75)
    (send p line-to 50 60)
    (send p close)
    p))

(define (draw-pkg dc x y logo)
  (define base-color "peru")
  (define no-pen (make-pen #:style 'transparent))
  (define middle-brush (make-brush #:color base-color))
  (define bright-brush (make-brush #:color (scale-color 1.2 base-color)))
  (define dim-brush (make-brush #:color (scale-color 0.8 base-color)))
  (define bright-pen (make-pen #:color (scale-color 1.2 base-color) #:width 1))

  (define old-p (send dc get-pen))
  (define old-b (send dc get-brush))
  (send dc set-pen no-pen)

  (send dc set-brush bright-brush)
  (send dc draw-path box-back-arms x y)

  (send dc set-brush dim-brush)
  (send dc draw-path box-inside x y)
  (when logo
    (define t (send dc get-transformation))
    (send dc translate (+ x 25) (+ y 20))
    (send dc scale 1/32 1/32)
    (send dc draw-bitmap logo 0 0)
    (send dc set-transformation t))

  (send dc set-brush middle-brush)
  (send dc draw-path box-base x y)

  (send dc set-brush bright-brush)
  (send dc draw-path box-front-arms x y)

  (send dc set-pen bright-pen)
  (send dc draw-line (+ x 50) (+ y 61) (+ x 50) (+ y 99))
  
  (send dc set-pen old-p)
  (send dc set-brush old-b))
