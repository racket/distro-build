#lang racket/base
(require racket/class
         racket/draw)

(define logo (read-bitmap "racket-logo.png"))

(define rising-W 683)
(define rising-H 385)

(define pkg-W 620)
(define pkg-H 418)

(define bm (make-bitmap rising-W rising-H #:backing-scale 2))
(define pkg-bm (make-bitmap pkg-W pkg-H #:backing-scale 2))

(define dc (send bm make-dc))
(define pkg-dc (send pkg-bm make-dc))

(send dc set-smoothing 'aligned)
(send pkg-dc set-smoothing 'aligned)

(send dc set-pen (make-pen #:style 'transparent))
(send dc set-brush (make-brush #:color (make-color 255 255 255)))
(send dc draw-rectangle 0 0 rising-W rising-H)

(send pkg-dc set-pen (make-pen #:style 'transparent))
(send pkg-dc set-brush (make-brush #:color (make-color 255 255 255)))
(send pkg-dc draw-rectangle 0 0 pkg-W pkg-H)

(send dc set-scale 0.5 0.5)
(send dc draw-bitmap logo -80 -180)
(send dc set-scale 1 1)

(send pkg-dc set-scale 0.25 0.25)
(send pkg-dc draw-bitmap logo -500 80)
(send pkg-dc set-scale 1 1)

;(send dc set-brush (make-brush #:color (make-color 255 255 255 0.75)))
;(send dc draw-rectangle 0 0 rising-W rising-H)

(send dc set-brush (make-brush #:color "white"))
(send dc draw-rounded-rectangle
      (* rising-W 0.1)
      (* rising-H 0.25)
      (* rising-W 0.8)
      (* rising-H 0.5))

(send pkg-dc set-brush (make-brush #:color (make-color 255 255 255 0.5)))
(send pkg-dc draw-rectangle 0 0 pkg-W pkg-H)

(define (make-arrow-path i)
  (let ([p (new dc-path%)])
    (define j (quotient i 2))
    (send p move-to i (- 10 i))
    (send p line-to i (+ -10 i))
    (send p line-to (+ 30 i) (+ -10 i))
    (send p line-to (+ 30 i) (+ -25 (* 2 i) j))
    (send p line-to (- 55 i j) 0)
    (send p line-to (+ 30 i) (- 25 (* 2 i) j))
    (send p line-to (+ 30 i) (- 10 i))
    (send p close)
    (send p scale 2 2)
    p))

(define X 280)
(define Y 190)
    
(send dc set-brush (make-brush #:color "forestgreen"))
(send dc draw-path (make-arrow-path 2) X Y)

(send dc set-pen (make-pen #:color "white" #:width 2))
(send dc set-brush (make-brush #:style 'transparent))
(send dc draw-path (make-arrow-path 2) X Y)

(send bm save-file "../distro-build-client/macosx-installer/racket-rising.png" 'png)
(send pkg-bm save-file "../distro-build-client/macosx-installer/pkg-bg.png" 'png)
