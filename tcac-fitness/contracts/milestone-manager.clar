;; Milestone Manager Contract
;; Handles milestone creation, verification, and tracking

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-GROUP (err u103))
(define-constant ERR-NOT-MEMBER (err u105))
(define-constant ERR-MILESTONE-NOT-FOUND (err u107))
(define-constant ERR-INVALID-VOTE (err u108))
(define-constant ERR-ALREADY-VOTED (err u109))
(define-constant ERR-INVALID-DESCRIPTION (err u113))
(define-constant ERR-INVALID-DEADLINE (err u114))
(define-constant ERR-MILESTONE-EXPIRED (err u115))
(define-constant ERR-MILESTONE-COMPLETED (err u116))
(define-constant ERR-INSUFFICIENT-VOTES (err u117))

;; Data Maps
(define-map group-members
    { group-id: uint, member: principal }
    { joined-at: uint }
)

(define-map milestones
    { group-id: uint, member: principal, milestone-id: uint }
    {
        description: (string-ascii 256),
        deadline: uint,
        completed: bool,
        completion-time: (optional uint),
        votes-required: uint,
        positive-votes: uint,
        negative-votes: uint,
        status: (string-ascii 10)  ;; pending, verified, rejected
    }
)

(define-map milestone-votes
    { group-id: uint, milestone-id: uint, voter: principal }
    { vote: bool }
)

(define-map member-milestones
    { group-id: uint, member: principal }
    {
        total-milestones: uint,
        completed-milestones: uint,
        verified-milestones: uint,
        last-milestone-id: uint
    }
)

;; Internal Functions
(define-private (is-valid-description (description (string-ascii 256)))
    (and 
        (>= (len description) u1)
        (<= (len description) u256)
    )
)

(define-private (is-valid-deadline (deadline uint))
    (> deadline block-height)
)

(define-private (is-group-member (group-id uint) (member principal))
    (is-some (map-get? group-members { group-id: group-id, member: member }))
)

;; Initialize member milestone stats if not exists
(define-private (init-member-stats (group-id uint) (member principal))
    (let 
        ((stats (map-get? member-milestones {group-id: group-id, member: member})))
        (match stats
            existing-stats existing-stats
            {
                total-milestones: u0,
                completed-milestones: u0,
                verified-milestones: u0,
                last-milestone-id: u0
            }
        )
    )
)

;; Public Functions
(define-public (add-milestone (group-id uint) (description (string-ascii 256)) (deadline uint))
    (let
        (
            (member tx-sender)
            (stats (init-member-stats group-id member))
            (new-milestone-id (+ (get last-milestone-id stats) u1))
        )
        (asserts! (is-valid-description description) ERR-INVALID-DESCRIPTION)
        (asserts! (is-valid-deadline deadline) ERR-INVALID-DEADLINE)
        (asserts! (is-group-member group-id member) ERR-NOT-MEMBER)
        
        (map-set milestones
            {group-id: group-id, member: member, milestone-id: new-milestone-id}
            {
                description: description,
                deadline: deadline,
                completed: false,
                completion-time: none,
                votes-required: u3,
                positive-votes: u0,
                negative-votes: u0,
                status: "pending"
            }
        )
        
        (map-set member-milestones
            {group-id: group-id, member: member}
            {
                total-milestones: (+ (get total-milestones stats) u1),
                completed-milestones: (get completed-milestones stats),
                verified-milestones: (get verified-milestones stats),
                last-milestone-id: new-milestone-id
            }
        )
        
        (ok new-milestone-id)
    )
)

(define-public (join-group (group-id uint))
    (let
        (
            (member tx-sender)
        )
        (asserts! (is-none (map-get? group-members { group-id: group-id, member: member }))
            ERR-ALREADY-VOTED)
        
        (map-set group-members
            { group-id: group-id, member: member }
            { joined-at: block-height }
        )
        (ok true)
    )
)

(define-public (complete-milestone (group-id uint) (milestone-id uint))
    (let
        (
            (member tx-sender)
            (milestone (unwrap! (map-get? milestones 
                {group-id: group-id, member: member, milestone-id: milestone-id})
                ERR-MILESTONE-NOT-FOUND))
        )
        (asserts! (is-group-member group-id member) ERR-NOT-MEMBER)
        (asserts! (not (get completed milestone)) ERR-MILESTONE-COMPLETED)
        (asserts! (<= block-height (get deadline milestone)) ERR-MILESTONE-EXPIRED)
        
        (map-set milestones
            {group-id: group-id, member: member, milestone-id: milestone-id}
            {
                description: (get description milestone),
                deadline: (get deadline milestone),
                completed: true,
                completion-time: (some block-height),
                votes-required: (get votes-required milestone),
                positive-votes: (get positive-votes milestone),
                negative-votes: (get negative-votes milestone),
                status: "pending"
            }
        )
        (ok true)
    )
)

(define-public (vote-milestone (group-id uint) (target-member principal) (milestone-id uint) (verify bool))
    (let
        (
            (voter tx-sender)
            (milestone (unwrap! (map-get? milestones 
                {group-id: group-id, member: target-member, milestone-id: milestone-id})
                ERR-MILESTONE-NOT-FOUND))
        )
        (asserts! (is-group-member group-id voter) ERR-NOT-MEMBER)
        (asserts! (not (is-eq voter target-member)) ERR-INVALID-VOTE)
        (asserts! (get completed milestone) ERR-INVALID-VOTE)
        (asserts! (is-none (map-get? milestone-votes 
            {group-id: group-id, milestone-id: milestone-id, voter: voter}))
            ERR-ALREADY-VOTED)
        
        ;; Record vote
        (map-set milestone-votes
            {group-id: group-id, milestone-id: milestone-id, voter: voter}
            {vote: verify}
        )
        
        ;; Update milestone votes
        (map-set milestones
            {group-id: group-id, member: target-member, milestone-id: milestone-id}
            {
                description: (get description milestone),
                deadline: (get deadline milestone),
                completed: (get completed milestone),
                completion-time: (get completion-time milestone),
                votes-required: (get votes-required milestone),
                positive-votes: (+ (get positive-votes milestone) (if verify u1 u0)),
                negative-votes: (+ (get negative-votes milestone) (if verify u0 u1)),
                status: (get status milestone)
            }
        )
        
        ;; Check if enough votes to verify/reject
        (if (>= (+ (get positive-votes milestone) (if verify u1 u0)) (get votes-required milestone))
            (finalize-milestone group-id target-member milestone-id true)
            (if (>= (+ (get negative-votes milestone) (if verify u0 u1)) (get votes-required milestone))
                (finalize-milestone group-id target-member milestone-id false)
                (ok true)
            )
        )
    )
)

(define-private (finalize-milestone (group-id uint) (member principal) (milestone-id uint) (verified bool))
    (let
        (
            (milestone (unwrap! (map-get? milestones 
                {group-id: group-id, member: member, milestone-id: milestone-id})
                ERR-MILESTONE-NOT-FOUND))
            (stats (unwrap! (map-get? member-milestones 
                {group-id: group-id, member: member})
                ERR-NOT-MEMBER))
        )
        (map-set milestones
            {group-id: group-id, member: member, milestone-id: milestone-id}
            {
                description: (get description milestone),
                deadline: (get deadline milestone),
                completed: (get completed milestone),
                completion-time: (get completion-time milestone),
                votes-required: (get votes-required milestone),
                positive-votes: (get positive-votes milestone),
                negative-votes: (get negative-votes milestone),
                status: (if verified "verified" "rejected")
            }
        )
        
        (if verified
            (begin
                (map-set member-milestones
                    {group-id: group-id, member: member}
                    {
                        total-milestones: (get total-milestones stats),
                        completed-milestones: (get completed-milestones stats),
                        verified-milestones: (+ (get verified-milestones stats) u1),
                        last-milestone-id: (get last-milestone-id stats)
                    }
                )
                (ok true)
            )
            (ok true)
        )
    )
)

;; Read-only Functions
(define-read-only (get-milestone (group-id uint) (member principal) (milestone-id uint))
    (map-get? milestones {group-id: group-id, member: member, milestone-id: milestone-id})
)

(define-read-only (get-member-milestone-stats (group-id uint) (member principal))
    (map-get? member-milestones {group-id: group-id, member: member})
)

(define-read-only (get-vote (group-id uint) (milestone-id uint) (voter principal))
    (map-get? milestone-votes {group-id: group-id, milestone-id: milestone-id, voter: voter})
)