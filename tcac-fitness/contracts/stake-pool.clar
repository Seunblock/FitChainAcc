;; Constants
(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-GROUP-FULL (err u101))
(define-constant ERR-INVALID-STAKE (err u102))
(define-constant ERR-GROUP-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-MEMBER (err u104))
(define-constant ERR-NOT-MEMBER (err u105))
(define-constant ERR-LOCKED-PERIOD (err u106))
(define-constant ERR-MILESTONE-NOT-FOUND (err u107))
(define-constant ERR-INVALID-VOTE (err u108))
(define-constant ERR-ALREADY-VOTED (err u109))
(define-constant MIN-GROUP-SIZE u5)
(define-constant MAX-GROUP-SIZE u10)
(define-constant MINIMUM-STAKE-AMOUNT u100)
(define-constant LOCK-PERIOD u90) ;; 90 days in blocks

;; Data Variables
(define-data-var total-groups uint u0)
(define-data-var total-stakes uint u0)

;; Data Maps
(define-map Groups
    { group-id: uint }
    {
        name: (string-ascii 64),
        focus-area: (string-ascii 32),
        start-time: uint,
        end-time: uint,
        total-stake: uint,
        active-members: uint,
        status: (string-ascii 20)  ;; "active" or "completed"
    }
)

(define-map GroupMembers
    { group-id: uint, member: principal }
    {
        stake-amount: uint,
        join-time: uint,
        reputation-score: uint,
        milestones-completed: uint,
        total-milestones: uint,
        withdrawn: bool
    }
)

(define-map Milestones
    { group-id: uint, member: principal, milestone-id: uint }
    {
        description: (string-ascii 256),
        deadline: uint,
        completed: bool,
        verified: bool,
        votes: uint
    }
)

(define-map MilestoneVotes
    { group-id: uint, milestone-id: uint, voter: principal }
    { voted: bool }
)

(define-map ReputationScores
    { member: principal }
    { score: uint }
)

;; Private Functions
(define-private (is-group-member (group-id uint) (member principal))
    (is-some (map-get? GroupMembers { group-id: group-id, member: member }))
)

(define-private (calculate-reward (group-id uint) (member principal))
    (let (
        (member-data (unwrap! (map-get? GroupMembers { group-id: group-id, member: member }) u0))
        (completed (get milestones-completed member-data))
        (total (get total-milestones member-data))
        (stake (get stake-amount member-data))
    )
    (if (> total u0)
        (/ (* stake completed) total)
        u0
    ))
)

;; Public Functions

;; Create a new accountability group
(define-public (create-group (name (string-ascii 64)) (focus-area (string-ascii 32)))
    (let ((new-group-id (+ (var-get total-groups) u1)))
        (begin
            (map-set Groups
                { group-id: new-group-id }
                {
                    name: name,
                    focus-area: focus-area,
                    start-time: block-height,
                    end-time: (+ block-height LOCK-PERIOD),
                    total-stake: u0,
                    active-members: u0,
                    status: "active"
                }
            )
            (var-set total-groups new-group-id)
            (ok new-group-id)
        )
    )
)

;; Join a group with stake
(define-public (join-group (group-id uint))
    (let (
        (group (unwrap! (map-get? Groups { group-id: group-id }) ERR-GROUP-NOT-FOUND))
        (current-members (get active-members group))
    )
    (if (and
            (<= current-members MAX-GROUP-SIZE)
            (not (is-group-member group-id tx-sender))
        )
        (begin
            (try! (stx-transfer? MINIMUM-STAKE-AMOUNT tx-sender (as-contract tx-sender)))
            (map-set GroupMembers
                { group-id: group-id, member: tx-sender }
                {
                    stake-amount: MINIMUM-STAKE-AMOUNT,
                    join-time: block-height,
                    reputation-score: u0,
                    milestones-completed: u0,
                    total-milestones: u0,
                    withdrawn: false
                }
            )
            (map-set Groups
                { group-id: group-id }
                (merge group {
                    active-members: (+ current-members u1),
                    total-stake: (+ (get total-stake group) MINIMUM-STAKE-AMOUNT)
                })
            )
            (ok true)
        )
        ERR-GROUP-FULL
    ))
)

;; Add a milestone
(define-public (add-milestone (group-id uint) (description (string-ascii 256)) (deadline uint))
    (let (
        (member-data (unwrap! (map-get? GroupMembers { group-id: group-id, member: tx-sender }) ERR-NOT-MEMBER))
        (milestone-id (get total-milestones member-data))
    )
    (begin
        (map-set Milestones
            { group-id: group-id, member: tx-sender, milestone-id: milestone-id }
            {
                description: description,
                deadline: deadline,
                completed: false,
                verified: false,
                votes: u0
            }
        )
        (map-set GroupMembers
            { group-id: group-id, member: tx-sender }
            (merge member-data {
                total-milestones: (+ milestone-id u1)
            })
        )
        (ok true)
    ))
)

;; Mark milestone as completed
(define-public (complete-milestone (group-id uint) (milestone-id uint))
    (let (
        (milestone (unwrap! (map-get? Milestones { group-id: group-id, member: tx-sender, milestone-id: milestone-id }) ERR-MILESTONE-NOT-FOUND))
        (member-data (unwrap! (map-get? GroupMembers { group-id: group-id, member: tx-sender }) ERR-NOT-MEMBER))
    )
    (begin
        (map-set Milestones
            { group-id: group-id, member: tx-sender, milestone-id: milestone-id }
            (merge milestone { completed: true })
        )
        (map-set GroupMembers
            { group-id: group-id, member: tx-sender }
            (merge member-data {
                milestones-completed: (+ (get milestones-completed member-data) u1)
            })
        )
        (ok true)
    ))
)

;; Vote on milestone completion
(define-public (vote-milestone (group-id uint) (member principal) (milestone-id uint) (verify bool))
    (let (
        (milestone (unwrap! (map-get? Milestones { group-id: group-id, member: member, milestone-id: milestone-id }) ERR-MILESTONE-NOT-FOUND))
        (has-voted (is-some (map-get? MilestoneVotes { group-id: group-id, milestone-id: milestone-id, voter: tx-sender })))
    )
    (if (and
            (is-group-member group-id tx-sender)
            (not has-voted)
        )
        (begin
            (map-set MilestoneVotes
                { group-id: group-id, milestone-id: milestone-id, voter: tx-sender }
                { voted: true }
            )
            (map-set Milestones
                { group-id: group-id, member: member, milestone-id: milestone-id }
                (merge milestone {
                    votes: (+ (get votes milestone) u1),
                    verified: (and verify (>= (+ (get votes milestone) u1) (/ MAX-GROUP-SIZE u2)))
                })
            )
            (ok true)
        )
        ERR-INVALID-VOTE
    ))
)

;; Withdraw rewards after lock period
(define-public (withdraw-rewards (group-id uint))
    (let (
        (group (unwrap! (map-get? Groups { group-id: group-id }) ERR-GROUP-NOT-FOUND))
        (member-data (unwrap! (map-get? GroupMembers { group-id: group-id, member: tx-sender }) ERR-NOT-MEMBER))
    )
    (if (and
            (>= block-height (get end-time group))
            (not (get withdrawn member-data))
        )
        (let (
            (reward-amount (calculate-reward group-id tx-sender))
        )
        (begin
            (try! (as-contract (stx-transfer? reward-amount (as-contract tx-sender) tx-sender)))
            (map-set GroupMembers
                { group-id: group-id, member: tx-sender }
                (merge member-data { withdrawn: true })
            )
            (ok reward-amount)
        ))
        ERR-LOCKED-PERIOD
    ))
)

;; Read-only functions

;; Get group details
(define-read-only (get-group-details (group-id uint))
    (map-get? Groups { group-id: group-id })
)

;; Get member details
(define-read-only (get-member-details (group-id uint) (member principal))
    (map-get? GroupMembers { group-id: group-id, member: member })
)

;; Get milestone details
(define-read-only (get-milestone-details (group-id uint) (member principal) (milestone-id uint))
    (map-get? Milestones { group-id: group-id, member: member, milestone-id: milestone-id })
)

;; Get member reputation
(define-read-only (get-reputation (member principal))
    (default-to { score: u0 } (map-get? ReputationScores { member: member }))
)