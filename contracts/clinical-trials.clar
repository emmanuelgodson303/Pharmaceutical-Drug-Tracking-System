;; Clinical Trial Management Contract
;; Tracks drug testing phases and results

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-TRIAL (err u201))
(define-constant ERR-TRIAL-EXISTS (err u202))
(define-constant ERR-INVALID-PHASE (err u203))
(define-constant ERR-INVALID-INPUT (err u204))
(define-constant ERR-TRIAL-NOT-ACTIVE (err u205))

;; Data Variables
(define-data-var next-trial-id uint u1)

;; Data Maps
(define-map clinical-trials
  { trial-id: uint }
  {
    drug-name: (string-ascii 100),
    sponsor: principal,
    principal-investigator: (string-ascii 100),
    trial-phase: uint,
    start-date: uint,
    estimated-end-date: uint,
    participant-count: uint,
    trial-status: (string-ascii 20),
    regulatory-approval: bool,
    primary-endpoint: (string-ascii 200)
  }
)

(define-map trial-results
  { trial-id: uint, phase: uint }
  {
    efficacy-rate: uint,
    safety-score: uint,
    adverse-events: uint,
    completion-rate: uint,
    statistical-significance: bool,
    result-summary: (string-ascii 500),
    approval-status: (string-ascii 20)
  }
)

(define-map authorized-sponsors
  { sponsor: principal }
  {
    organization-name: (string-ascii 100),
    license-number: (string-ascii 50),
    authorization-date: uint,
    is-authorized: bool
  }
)

(define-map trial-milestones
  { trial-id: uint, milestone-id: uint }
  {
    milestone-name: (string-ascii 100),
    target-date: uint,
    completion-date: (optional uint),
    is-completed: bool,
    notes: (string-ascii 200)
  }
)

;; Private Functions
(define-private (is-authorized-sponsor (sponsor principal))
  (default-to false
    (get is-authorized
      (map-get? authorized-sponsors { sponsor: sponsor }))))

(define-private (is-valid-phase (phase uint))
  (and (>= phase u1) (<= phase u4)))

(define-private (validate-percentage (value uint))
  (and (>= value u0) (<= value u100)))

;; Public Functions

;; Authorize a trial sponsor
(define-public (authorize-sponsor
  (sponsor principal)
  (organization-name (string-ascii 100))
  (license-number (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len organization-name) u0) ERR-INVALID-INPUT)
    (ok (map-set authorized-sponsors
      { sponsor: sponsor }
      {
        organization-name: organization-name,
        license-number: license-number,
        authorization-date: block-height,
        is-authorized: true
      }))))

;; Register a new clinical trial
(define-public (register-trial
  (drug-name (string-ascii 100))
  (principal-investigator (string-ascii 100))
  (trial-phase uint)
  (estimated-end-date uint)
  (participant-count uint)
  (primary-endpoint (string-ascii 200)))
  (let ((trial-id (var-get next-trial-id)))
    (asserts! (is-authorized-sponsor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-phase trial-phase) ERR-INVALID-PHASE)
    (asserts! (> estimated-end-date block-height) ERR-INVALID-INPUT)
    (asserts! (> participant-count u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? clinical-trials { trial-id: trial-id })) ERR-TRIAL-EXISTS)
    (map-set clinical-trials
      { trial-id: trial-id }
      {
        drug-name: drug-name,
        sponsor: tx-sender,
        principal-investigator: principal-investigator,
        trial-phase: trial-phase,
        start-date: block-height,
        estimated-end-date: estimated-end-date,
        participant-count: participant-count,
        trial-status: "ACTIVE",
        regulatory-approval: false,
        primary-endpoint: primary-endpoint
      })
    (var-set next-trial-id (+ trial-id u1))
    (ok trial-id)))

;; Submit trial results
(define-public (submit-results
  (trial-id uint)
  (phase uint)
  (efficacy-rate uint)
  (safety-score uint)
  (adverse-events uint)
  (completion-rate uint)
  (statistical-significance bool)
  (result-summary (string-ascii 500)))
  (let ((trial-data (unwrap! (map-get? clinical-trials { trial-id: trial-id }) ERR-INVALID-TRIAL)))
    (asserts! (is-eq tx-sender (get sponsor trial-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq phase (get trial-phase trial-data)) ERR-INVALID-PHASE)
    (asserts! (validate-percentage efficacy-rate) ERR-INVALID-INPUT)
    (asserts! (validate-percentage safety-score) ERR-INVALID-INPUT)
    (asserts! (validate-percentage completion-rate) ERR-INVALID-INPUT)
    (ok (map-set trial-results
      { trial-id: trial-id, phase: phase }
      {
        efficacy-rate: efficacy-rate,
        safety-score: safety-score,
        adverse-events: adverse-events,
        completion-rate: completion-rate,
        statistical-significance: statistical-significance,
        result-summary: result-summary,
        approval-status: "PENDING"
      }))))

;; Update trial status
(define-public (update-trial-status
  (trial-id uint)
  (new-status (string-ascii 20)))
  (let ((trial-data (unwrap! (map-get? clinical-trials { trial-id: trial-id }) ERR-INVALID-TRIAL)))
    (asserts! (is-eq tx-sender (get sponsor trial-data)) ERR-NOT-AUTHORIZED)
    (ok (map-set clinical-trials
      { trial-id: trial-id }
      (merge trial-data { trial-status: new-status })))))

;; Add trial milestone
(define-public (add-milestone
  (trial-id uint)
  (milestone-id uint)
  (milestone-name (string-ascii 100))
  (target-date uint)
  (notes (string-ascii 200)))
  (let ((trial-data (unwrap! (map-get? clinical-trials { trial-id: trial-id }) ERR-INVALID-TRIAL)))
    (asserts! (is-eq tx-sender (get sponsor trial-data)) ERR-NOT-AUTHORIZED)
    (asserts! (> target-date block-height) ERR-INVALID-INPUT)
    (ok (map-set trial-milestones
      { trial-id: trial-id, milestone-id: milestone-id }
      {
        milestone-name: milestone-name,
        target-date: target-date,
        completion-date: none,
        is-completed: false,
        notes: notes
      }))))

;; Approve trial results
(define-public (approve-results (trial-id uint) (phase uint))
  (let ((result-data (unwrap! (map-get? trial-results { trial-id: trial-id, phase: phase }) ERR-INVALID-TRIAL)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set trial-results
      { trial-id: trial-id, phase: phase }
      (merge result-data { approval-status: "APPROVED" })))))

;; Read-only functions
(define-read-only (get-trial-info (trial-id uint))
  (map-get? clinical-trials { trial-id: trial-id }))

(define-read-only (get-trial-results (trial-id uint) (phase uint))
  (map-get? trial-results { trial-id: trial-id, phase: phase }))

(define-read-only (get-sponsor-info (sponsor principal))
  (map-get? authorized-sponsors { sponsor: sponsor }))

(define-read-only (get-milestone (trial-id uint) (milestone-id uint))
  (map-get? trial-milestones { trial-id: trial-id, milestone-id: milestone-id }))

(define-read-only (get-next-trial-id)
  (var-get next-trial-id))
