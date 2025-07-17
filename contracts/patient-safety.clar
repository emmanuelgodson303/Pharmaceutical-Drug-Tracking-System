;; Patient Safety Monitoring Contract
;; Tracks adverse drug reactions and patient outcomes

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-REPORT (err u501))
(define-constant ERR-REPORT-EXISTS (err u502))
(define-constant ERR-INVALID-INPUT (err u503))
(define-constant ERR-INVALID-SEVERITY (err u504))
(define-constant ERR-PATIENT-NOT-FOUND (err u505))

;; Data Variables
(define-data-var next-adr-id uint u1)
(define-data-var next-alert-id uint u1)

;; Data Maps
(define-map adverse-drug-reactions
  { adr-id: uint }
  {
    patient-id: (string-ascii 50),
    reporter: principal,
    drug-name: (string-ascii 100),
    batch-number: (string-ascii 50),
    reaction-description: (string-ascii 500),
    severity-level: uint,
    onset-date: uint,
    report-date: uint,
    outcome: (string-ascii 50),
    causality-assessment: (string-ascii 20),
    follow-up-required: bool
  }
)

(define-map safety-alerts
  { alert-id: uint }
  {
    drug-name: (string-ascii 100),
    alert-type: (string-ascii 50),
    severity-level: uint,
    alert-description: (string-ascii 500),
    issue-date: uint,
    expiry-date: uint,
    affected-batches: (string-ascii 200),
    recommended-action: (string-ascii 300),
    is-active: bool
  }
)

(define-map authorized-reporters
  { reporter: principal }
  {
    reporter-name: (string-ascii 100),
    organization: (string-ascii 100),
    reporter-type: (string-ascii 50),
    authorization-date: uint,
    is-authorized: bool
  }
)

(define-map patient-outcomes
  { patient-id: (string-ascii 50), outcome-id: uint }
  {
    drug-name: (string-ascii 100),
    treatment-start: uint,
    treatment-end: (optional uint),
    outcome-type: (string-ascii 50),
    outcome-description: (string-ascii 300),
    reporter: principal,
    follow-up-date: (optional uint)
  }
)

(define-map drug-safety-profiles
  { drug-name: (string-ascii 100) }
  {
    total-reports: uint,
    serious-reactions: uint,
    mild-reactions: uint,
    last-updated: uint,
    safety-score: uint,
    monitoring-status: (string-ascii 20)
  }
)

;; Private Functions
(define-private (is-authorized-reporter (reporter principal))
  (default-to false
    (get is-authorized
      (map-get? authorized-reporters { reporter: reporter }))))

(define-private (validate-severity-level (level uint))
  (and (>= level u1) (<= level u5)))

(define-private (update-safety-profile (drug-name (string-ascii 100)) (severity uint))
  (let ((current-profile (default-to
    { total-reports: u0, serious-reactions: u0, mild-reactions: u0, last-updated: u0, safety-score: u100, monitoring-status: "NORMAL" }
    (map-get? drug-safety-profiles { drug-name: drug-name }))))
    (let ((new-total (+ (get total-reports current-profile) u1))
          (new-serious (if (>= severity u4) (+ (get serious-reactions current-profile) u1) (get serious-reactions current-profile)))
          (new-mild (if (< severity u4) (+ (get mild-reactions current-profile) u1) (get mild-reactions current-profile))))
      (map-set drug-safety-profiles
        { drug-name: drug-name }
        (merge current-profile {
          total-reports: new-total,
          serious-reactions: new-serious,
          mild-reactions: new-mild,
          last-updated: block-height
        })))))

;; Public Functions

;; Authorize a safety reporter
(define-public (authorize-reporter
  (reporter principal)
  (reporter-name (string-ascii 100))
  (organization (string-ascii 100))
  (reporter-type (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len reporter-name) u0) ERR-INVALID-INPUT)
    (ok (map-set authorized-reporters
      { reporter: reporter }
      {
        reporter-name: reporter-name,
        organization: organization,
        reporter-type: reporter-type,
        authorization-date: block-height,
        is-authorized: true
      }))))

;; Report adverse drug reaction
(define-public (report-adr
  (patient-id (string-ascii 50))
  (drug-name (string-ascii 100))
  (batch-number (string-ascii 50))
  (reaction-description (string-ascii 500))
  (severity-level uint)
  (onset-date uint)
  (outcome (string-ascii 50))
  (causality-assessment (string-ascii 20)))
  (let ((adr-id (var-get next-adr-id)))
    (asserts! (is-authorized-reporter tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (validate-severity-level severity-level) ERR-INVALID-SEVERITY)
    (asserts! (> (len patient-id) u0) ERR-INVALID-INPUT)
    (asserts! (> (len drug-name) u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? adverse-drug-reactions { adr-id: adr-id })) ERR-REPORT-EXISTS)
    (map-set adverse-drug-reactions
      { adr-id: adr-id }
      {
        patient-id: patient-id,
        reporter: tx-sender,
        drug-name: drug-name,
        batch-number: batch-number,
        reaction-description: reaction-description,
        severity-level: severity-level,
        onset-date: onset-date,
        report-date: block-height,
        outcome: outcome,
        causality-assessment: causality-assessment,
        follow-up-required: (>= severity-level u4)
      })
    (update-safety-profile drug-name severity-level)
    (var-set next-adr-id (+ adr-id u1))
    (ok adr-id)))

;; Issue safety alert
(define-public (issue-safety-alert
  (drug-name (string-ascii 100))
  (alert-type (string-ascii 50))
  (severity-level uint)
  (alert-description (string-ascii 500))
  (expiry-date uint)
  (affected-batches (string-ascii 200))
  (recommended-action (string-ascii 300)))
  (let ((alert-id (var-get next-alert-id)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (validate-severity-level severity-level) ERR-INVALID-SEVERITY)
    (asserts! (> expiry-date block-height) ERR-INVALID-INPUT)
    (asserts! (> (len drug-name) u0) ERR-INVALID-INPUT)
    (map-set safety-alerts
      { alert-id: alert-id }
      {
        drug-name: drug-name,
        alert-type: alert-type,
        severity-level: severity-level,
        alert-description: alert-description,
        issue-date: block-height,
        expiry-date: expiry-date,
        affected-batches: affected-batches,
        recommended-action: recommended-action,
        is-active: true
      })
    (var-set next-alert-id (+ alert-id u1))
    (ok alert-id)))

;; Record patient outcome
(define-public (record-patient-outcome
  (patient-id (string-ascii 50))
  (outcome-id uint)
  (drug-name (string-ascii 100))
  (treatment-start uint)
  (treatment-end (optional uint))
  (outcome-type (string-ascii 50))
  (outcome-description (string-ascii 300))
  (follow-up-date (optional uint)))
  (begin
    (asserts! (is-authorized-reporter tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> (len patient-id) u0) ERR-INVALID-INPUT)
    (asserts! (> (len drug-name) u0) ERR-INVALID-INPUT)
    (ok (map-set patient-outcomes
      { patient-id: patient-id, outcome-id: outcome-id }
      {
        drug-name: drug-name,
        treatment-start: treatment-start,
        treatment-end: treatment-end,
        outcome-type: outcome-type,
        outcome-description: outcome-description,
        reporter: tx-sender,
        follow-up-date: follow-up-date
      }))))

;; Update ADR follow-up
(define-public (update-adr-followup
  (adr-id uint)
  (new-outcome (string-ascii 50))
  (causality-assessment (string-ascii 20)))
  (let ((adr-data (unwrap! (map-get? adverse-drug-reactions { adr-id: adr-id }) ERR-INVALID-REPORT)))
    (asserts! (is-eq tx-sender (get reporter adr-data)) ERR-NOT-AUTHORIZED)
    (ok (map-set adverse-drug-reactions
      { adr-id: adr-id }
      (merge adr-data {
        outcome: new-outcome,
        causality-assessment: causality-assessment,
        follow-up-required: false
      })))))

;; Deactivate safety alert
(define-public (deactivate-alert (alert-id uint))
  (let ((alert-data (unwrap! (map-get? safety-alerts { alert-id: alert-id }) ERR-INVALID-REPORT)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set safety-alerts
      { alert-id: alert-id }
      (merge alert-data { is-active: false })))))

;; Update drug safety profile monitoring status
(define-public (update-monitoring-status
  (drug-name (string-ascii 100))
  (new-status (string-ascii 20))
  (new-safety-score uint))
  (let ((profile-data (unwrap! (map-get? drug-safety-profiles { drug-name: drug-name }) ERR-INVALID-INPUT)))
    (asserts! (<= new-safety-score u100) ERR-INVALID-INPUT)
    (ok (map-set drug-safety-profiles
      { drug-name: drug-name }
      (merge profile-data {
        monitoring-status: new-status,
        safety-score: new-safety-score,
        last-updated: block-height
      })))))

;; Read-only functions
(define-read-only (get-adr-info (adr-id uint))
  (map-get? adverse-drug-reactions { adr-id: adr-id }))

(define-read-only (get-safety-alert (alert-id uint))
  (map-get? safety-alerts { alert-id: alert-id }))

(define-read-only (get-reporter-info (reporter principal))
  (map-get? authorized-reporters { reporter: reporter }))

(define-read-only (get-patient-outcome (patient-id (string-ascii 50)) (outcome-id uint))
  (map-get? patient-outcomes { patient-id: patient-id, outcome-id: outcome-id }))

(define-read-only (get-drug-safety-profile (drug-name (string-ascii 100)))
  (map-get? drug-safety-profiles { drug-name: drug-name }))

(define-read-only (get-next-adr-id)
  (var-get next-adr-id))

(define-read-only (get-next-alert-id)
  (var-get next-alert-id))
