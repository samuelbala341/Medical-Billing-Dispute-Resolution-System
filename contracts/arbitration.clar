;; Arbitration Management Contract
;; Handles arbitrator assignment, decisions, and performance tracking

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-ARBITRATOR-NOT-FOUND (err u401))
(define-constant ERR-CASE-NOT-FOUND (err u402))
(define-constant ERR-INVALID-DECISION (err u403))
(define-constant ERR-ALREADY-ASSIGNED (err u404))
(define-constant ERR-INVALID-RATING (err u405))

;; Data Variables
(define-data-var next-case-id uint u1)
(define-data-var next-arbitrator-id uint u1)

;; Data Maps
(define-map arbitrators
  { id: uint }
  {
    address: principal,
    name: (string-ascii 100),
    specialization: (string-ascii 50),
    active: bool,
    cases-handled: uint,
    success-rate: uint,
    average-rating: uint,
    registered-at: uint
  }
)

(define-map arbitration-cases
  { id: uint }
  {
    dispute-id: uint,
    arbitrator-id: uint,
    status: (string-ascii 20),
    decision: (optional (string-ascii 500)),
    reasoning: (optional (string-ascii 1000)),
    created-at: uint,
    decided-at: (optional uint)
  }
)

(define-map case-assignments
  { dispute-id: uint }
  { case-id: uint, arbitrator-id: uint }
)

(define-map arbitrator-performance
  { arbitrator-id: uint, case-id: uint }
  {
    decision-time: uint,
    rating: uint,
    feedback: (string-ascii 300)
  }
)

;; Private Functions
(define-private (is-valid-decision (decision (string-ascii 500)))
  (and
    (> (len decision) u0)
    (< (len decision) u501)
  )
)

(define-private (is-valid-specialization (specialization (string-ascii 50)))
  (or
    (is-eq specialization "medical-billing")
    (is-eq specialization "insurance-claims")
    (is-eq specialization "healthcare-law")
    (is-eq specialization "general-arbitration")
  )
)

(define-private (calculate-success-rate (cases-handled uint) (successful-cases uint))
  (if (is-eq cases-handled u0)
    u0
    (/ (* successful-cases u100) cases-handled)
  )
)

;; Public Functions
(define-public (register-arbitrator (name (string-ascii 100)) (specialization (string-ascii 50)))
  (let
    (
      (arbitrator-id (var-get next-arbitrator-id))
    )
    (asserts! (< (len name) u101) ERR-INVALID-DECISION)
    (asserts! (is-valid-specialization specialization) ERR-INVALID-DECISION)

    (map-set arbitrators
      { id: arbitrator-id }
      {
        address: tx-sender,
        name: name,
        specialization: specialization,
        active: true,
        cases-handled: u0,
        success-rate: u0,
        average-rating: u0,
        registered-at: block-height
      }
    )

    (var-set next-arbitrator-id (+ arbitrator-id u1))
    (ok arbitrator-id)
  )
)

(define-public (assign-arbitrator (dispute-id uint) (arbitrator-id uint))
  (let
    (
      (case-id (var-get next-case-id))
      (arbitrator (unwrap! (map-get? arbitrators { id: arbitrator-id }) ERR-ARBITRATOR-NOT-FOUND))
      (existing-assignment (map-get? case-assignments { dispute-id: dispute-id }))
    )
    (asserts! (is-none existing-assignment) ERR-ALREADY-ASSIGNED)
    (asserts! (get active arbitrator) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set arbitration-cases
      { id: case-id }
      {
        dispute-id: dispute-id,
        arbitrator-id: arbitrator-id,
        status: "assigned",
        decision: none,
        reasoning: none,
        created-at: block-height,
        decided-at: none
      }
    )

    (map-set case-assignments
      { dispute-id: dispute-id }
      { case-id: case-id, arbitrator-id: arbitrator-id }
    )

    (var-set next-case-id (+ case-id u1))
    (ok case-id)
  )
)

(define-public (submit-decision (case-id uint) (decision (string-ascii 500)) (reasoning (string-ascii 1000)))
  (let
    (
      (case-data (unwrap! (map-get? arbitration-cases { id: case-id }) ERR-CASE-NOT-FOUND))
      (arbitrator (unwrap! (map-get? arbitrators { id: (get arbitrator-id case-data) }) ERR-ARBITRATOR-NOT-FOUND))
    )
    (asserts! (is-valid-decision decision) ERR-INVALID-DECISION)
    (asserts! (< (len reasoning) u1001) ERR-INVALID-DECISION)
    (asserts! (is-eq tx-sender (get address arbitrator)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status case-data) "assigned") ERR-INVALID-DECISION)

    (map-set arbitration-cases
      { id: case-id }
      (merge case-data {
        status: "decided",
        decision: (some decision),
        reasoning: (some reasoning),
        decided-at: (some block-height)
      })
    )

    ;; Update arbitrator stats
    (map-set arbitrators
      { id: (get arbitrator-id case-data) }
      (merge arbitrator {
        cases-handled: (+ (get cases-handled arbitrator) u1)
      })
    )

    (ok true)
  )
)

(define-public (rate-arbitrator (case-id uint) (rating uint) (feedback (string-ascii 300)))
  (let
    (
      (case-data (unwrap! (map-get? arbitration-cases { id: case-id }) ERR-CASE-NOT-FOUND))
      (arbitrator (unwrap! (map-get? arbitrators { id: (get arbitrator-id case-data) }) ERR-ARBITRATOR-NOT-FOUND))
    )
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-RATING)
    (asserts! (< (len feedback) u301) ERR-INVALID-DECISION)
    (asserts! (is-eq (get status case-data) "decided") ERR-INVALID-DECISION)

    (map-set arbitrator-performance
      { arbitrator-id: (get arbitrator-id case-data), case-id: case-id }
      {
        decision-time: (- (unwrap-panic (get decided-at case-data)) (get created-at case-data)),
        rating: rating,
        feedback: feedback
      }
    )
    (ok true)
  )
)

(define-public (deactivate-arbitrator (arbitrator-id uint))
  (let
    (
      (arbitrator (unwrap! (map-get? arbitrators { id: arbitrator-id }) ERR-ARBITRATOR-NOT-FOUND))
    )
    (asserts! (or
      (is-eq tx-sender (get address arbitrator))
      (is-eq tx-sender CONTRACT-OWNER)
    ) ERR-NOT-AUTHORIZED)

    (map-set arbitrators
      { id: arbitrator-id }
      (merge arbitrator { active: false })
    )
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-arbitrator (arbitrator-id uint))
  (map-get? arbitrators { id: arbitrator-id })
)

(define-read-only (get-case (case-id uint))
  (map-get? arbitration-cases { id: case-id })
)

(define-read-only (get-case-by-dispute (dispute-id uint))
  (match (map-get? case-assignments { dispute-id: dispute-id })
    assignment (map-get? arbitration-cases { id: (get case-id assignment) })
    none
  )
)

(define-read-only (get-arbitrator-performance (arbitrator-id uint) (case-id uint))
  (map-get? arbitrator-performance { arbitrator-id: arbitrator-id, case-id: case-id })
)

(define-read-only (get-next-case-id)
  (var-get next-case-id)
)

(define-read-only (get-next-arbitrator-id)
  (var-get next-arbitrator-id)
)

(define-read-only (is-arbitrator-active (arbitrator-id uint))
  (match (map-get? arbitrators { id: arbitrator-id })
    arbitrator (get active arbitrator)
    false
  )
)
