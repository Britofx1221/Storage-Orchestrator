;; File sharing smart contract

(define-constant contract-administrator tx-sender)
(define-constant ERROR-ADMIN-ONLY (err u100))
(define-constant ERROR-FILE-NOT-FOUND (err u101))
(define-constant ERROR-ACCESS-DENIED (err u102))
(define-constant ERROR-INVALID-PARAMETERS (err u103))
(define-constant ERROR-DUPLICATE-FILE (err u104))
(define-constant ERROR-STORAGE-EXCEEDED (err u105))

;; Storage Constants
(define-constant maximum-file-size-bytes u1073741824) ;; 1GB in bytes
(define-constant maximum-files-allowed-per-user u100)
(define-constant minimum-required-file-name-length u1)
(define-constant minimum-required-description-length u1)

;; Data Maps
(define-map file-metadata 
    { file-identifier: uint }
    {
        file-owner: principal,
        file-display-name: (string-ascii 64),
        content-hash: (string-ascii 64),
        content-size-bytes: uint,
        creation-timestamp: uint,
        modification-timestamp: uint,
        content-mime-type: (string-ascii 32),
        content-description: (string-ascii 256),
        visibility-private: bool,
        encryption-enabled: bool,
        current-version: uint
    }
)

(define-map user-file-permissions 
    { file-identifier: uint, authorized-user: principal } 
    { 
        read-permission: bool,
        write-permission: bool,
        permission-grant-date: uint,
        permission-expiry-date: (optional uint)
    }
)

(define-map user-storage-metrics
    { account-owner: principal }
    {
        total-file-count: uint,
        total-storage-bytes: uint,
        last-activity-timestamp: uint
    }
)

(define-map file-modification-history
    { file-identifier: uint, version-identifier: uint }
    {
        content-hash: (string-ascii 64),
        content-size-bytes: uint,
        modifier-principal: principal,
        modification-date: uint,
        modification-notes: (string-ascii 256)
    }
)

(define-map file-categorization
    { file-identifier: uint }
    { category-tags: (list 10 (string-ascii 32)) }
)

(define-data-var file-sequence-counter uint u0)

;; Private Functions
(define-private (is-owner-of-file (file-identifier uint))
    (match (map-get? file-metadata { file-identifier: file-identifier })
        file-record (is-eq (get file-owner file-record) tx-sender)
        false
    )
)

(define-private (validate-file-exists (file-identifier uint))
    (match (map-get? file-metadata { file-identifier: file-identifier })
        file-record (ok true)
        ERROR-FILE-NOT-FOUND
    )
)

(define-private (validate-user-account (account-principal principal))
    (if (is-eq account-principal contract-administrator)
        ERROR-INVALID-PARAMETERS
        (ok true)
    )
)

(define-private (validate-file-name-length (file-display-name (string-ascii 64)))
    (if (and 
            (>= (len file-display-name) minimum-required-file-name-length)
            (<= (len file-display-name) u64)
        )
        (ok true)
        ERROR-INVALID-PARAMETERS
    )
)

(define-private (validate-description-length (content-description (string-ascii 256)))
    (if (and
            (>= (len content-description) minimum-required-description-length)
            (<= (len content-description) u256)
        )
        (ok true)
        ERROR-INVALID-PARAMETERS
    )
)

(define-private (validate-expiration-date (expiration-date (optional uint)))
    (match expiration-date
        specified-date (if (> specified-date block-height)
            (ok true)
            ERROR-INVALID-PARAMETERS)
        (ok true)
    )
)

(define-private (validate-content-hash (content-hash (string-ascii 64)))
    (if (is-eq (len content-hash) u64)
        (ok true)
        ERROR-INVALID-PARAMETERS
    )
)

(define-private (validate-mime-type (content-mime-type (string-ascii 32)))
    (if (<= (len content-mime-type) u32)
        (ok true)
        ERROR-INVALID-PARAMETERS
    )
)

(define-private (validate-category-tags (category-tags (list 10 (string-ascii 32))))
    (if (<= (len category-tags) u10)
        (ok (fold check-tag-length category-tags true))
        ERROR-INVALID-PARAMETERS
    )
)

(define-private (check-tag-length (tag (string-ascii 32)) (valid bool))
    (and valid (<= (len tag) u32))
)

(define-private (validate-file-identifier (file-identifier uint))
    (if (> file-identifier u0)
        (ok true)
        ERROR-INVALID-PARAMETERS
    )
)

(define-private (has-read-access (file-identifier uint) (account-principal principal))
    (match (map-get? file-metadata { file-identifier: file-identifier })
        file-record 
            (let ((permission-entry (map-get? user-file-permissions { file-identifier: file-identifier, authorized-user: account-principal })))
                (or 
                    (is-eq (get file-owner file-record) account-principal)
                    (not (get visibility-private file-record))
                    (match permission-entry
                        permission (and 
                            (get read-permission permission)
                            (match (get permission-expiry-date permission)
                                expiry-date (> expiry-date block-height)
                                true
                            )
                        )
                        false
                    )
                )
            )
        false
    )
)

(define-private (has-write-access (file-identifier uint) (account-principal principal))
    (match (map-get? user-file-permissions { file-identifier: file-identifier, authorized-user: account-principal })
        permission (and
            (get write-permission permission)
            (match (get permission-expiry-date permission)
                expiry-date (> expiry-date block-height)
                true
            )
        )
        false
    )
)

(define-private (update-storage-metrics (account-principal principal) (storage-change-bytes int))
    (let (
        (current-metrics (default-to 
            { total-file-count: u0, total-storage-bytes: u0, last-activity-timestamp: u0 }
            (map-get? user-storage-metrics { account-owner: account-principal })
        ))
        (updated-file-count (+ (get total-file-count current-metrics) u1))
        (updated-storage-bytes (+ (get total-storage-bytes current-metrics) 
            (if (> storage-change-bytes 0) 
                (to-uint storage-change-bytes) 
                (if (>= (get total-storage-bytes current-metrics) (to-uint (if (< storage-change-bytes 0) (- 0 storage-change-bytes) storage-change-bytes)))
                    (to-uint (if (< storage-change-bytes 0) (- 0 storage-change-bytes) storage-change-bytes))
                    u0
                )
            )))
    )
        (map-set user-storage-metrics
            { account-owner: account-principal }
            {
                total-file-count: updated-file-count,
                total-storage-bytes: updated-storage-bytes,
                last-activity-timestamp: block-height
            }
        )
    )
)

;; Public Functions
(define-public (upload-file 
    (file-display-name (string-ascii 64)) 
    (content-hash (string-ascii 64)) 
    (content-size-bytes uint)
    (content-mime-type (string-ascii 32))
    (content-description (string-ascii 256))
    (visibility-private bool)
    (encryption-enabled bool)
    (category-tags (list 10 (string-ascii 32)))
)
    (let (
        (new-file-identifier (+ (var-get file-sequence-counter) u1))
        (user-metrics (default-to 
            { total-file-count: u0, total-storage-bytes: u0, last-activity-timestamp: u0 }
            (map-get? user-storage-metrics { account-owner: tx-sender })
        ))
    )
        ;; Input validation
        (try! (validate-file-name-length file-display-name))
        (try! (validate-description-length content-description))
        (try! (validate-content-hash content-hash))
        (try! (validate-mime-type content-mime-type))
        (try! (validate-category-tags category-tags))
        (asserts! (<= content-size-bytes maximum-file-size-bytes) ERROR-INVALID-PARAMETERS)
        (asserts! (< (get total-file-count user-metrics) maximum-files-allowed-per-user) ERROR-STORAGE-EXCEEDED)
        
        (var-set file-sequence-counter new-file-identifier)
        (map-set file-metadata
            { file-identifier: new-file-identifier }
            {
                file-owner: tx-sender,
                file-display-name: file-display-name,
                content-hash: content-hash,
                content-size-bytes: content-size-bytes,
                creation-timestamp: block-height,
                modification-timestamp: block-height,
                content-mime-type: content-mime-type,
                content-description: content-description,
                visibility-private: visibility-private,
                encryption-enabled: encryption-enabled,
                current-version: u1
            }
        )
        
        (map-set file-categorization { file-identifier: new-file-identifier } { category-tags: category-tags })
        (map-set file-modification-history
            { file-identifier: new-file-identifier, version-identifier: u1 }
            {
                content-hash: content-hash,
                content-size-bytes: content-size-bytes,
                modifier-principal: tx-sender,
                modification-date: block-height,
                modification-notes: "Initial file upload"
            }
        )
        
        (update-storage-metrics tx-sender (to-int content-size-bytes))
        (ok new-file-identifier)
    )
)

(define-public (update-file 
    (file-identifier uint)
    (updated-content-hash (string-ascii 64))
    (updated-size-bytes uint)
    (modification-notes (string-ascii 256))
)
    (begin
        (try! (validate-file-identifier file-identifier))
        (try! (validate-file-exists file-identifier))
        (try! (validate-description-length modification-notes))
        (try! (validate-content-hash updated-content-hash))
        
        (match (map-get? file-metadata { file-identifier: file-identifier })
            file-record
                (let ((next-version-number (+ (get current-version file-record) u1)))
                    (asserts! (or (is-owner-of-file file-identifier) (has-write-access file-identifier tx-sender)) ERROR-ACCESS-DENIED)
                    (asserts! (<= updated-size-bytes maximum-file-size-bytes) ERROR-INVALID-PARAMETERS)
                    
                    (map-set file-metadata
                        { file-identifier: file-identifier }
                        (merge file-record {
                            content-hash: updated-content-hash,
                            content-size-bytes: updated-size-bytes,
                            modification-timestamp: block-height,
                            current-version: next-version-number
                        })
                    )
                    
                    (map-set file-modification-history
                        { file-identifier: file-identifier, version-identifier: next-version-number }
                        {
                            content-hash: updated-content-hash,
                            content-size-bytes: updated-size-bytes,
                            modifier-principal: tx-sender,
                            modification-date: block-height,
                            modification-notes: modification-notes
                        }
                    )
                    
                    (update-storage-metrics (get file-owner file-record) (- (to-int updated-size-bytes) (to-int (get content-size-bytes file-record))))
                    (ok next-version-number)
                )
            ERROR-FILE-NOT-FOUND
        )
    )
)

(define-public (grant-access 
    (file-identifier uint) 
    (authorized-user principal)
    (write-permission bool)
    (permission-expiry-date (optional uint))
)
    (begin
        (try! (validate-file-identifier file-identifier))
        (try! (validate-file-exists file-identifier))
        (try! (validate-user-account authorized-user))
        (try! (validate-expiration-date permission-expiry-date))
        (asserts! (is-owner-of-file file-identifier) ERROR-ACCESS-DENIED)
        
        (map-set user-file-permissions
            { file-identifier: file-identifier, authorized-user: authorized-user }
            {
                read-permission: true,
                write-permission: write-permission,
                permission-grant-date: block-height,
                permission-expiry-date: permission-expiry-date
            }
        )
        (ok true)
    )
)

(define-public (update-metadata
    (file-identifier uint)
    (new-display-name (optional (string-ascii 64)))
    (new-description (optional (string-ascii 256)))
    (new-category-tags (optional (list 10 (string-ascii 32))))
)
    (begin
        (try! (validate-file-identifier file-identifier))
        (try! (validate-file-exists file-identifier))
        
        (match (map-get? file-metadata { file-identifier: file-identifier })
            file-record
                (begin
                    (asserts! (is-owner-of-file file-identifier) ERROR-ACCESS-DENIED)
                    
                    (match new-display-name
                        display-name (try! (validate-file-name-length display-name))
                        true
                    )
                    
                    (match new-description
                        description (try! (validate-description-length description))
                        true
                    )
                    
                    (match new-category-tags
                        category-tags (try! (validate-category-tags category-tags))
                        true
                    )
                    
                    (if (is-some new-display-name)
                        (map-set file-metadata
                            { file-identifier: file-identifier }
                            (merge file-record { file-display-name: (unwrap! new-display-name ERROR-INVALID-PARAMETERS) })
                        )
                        true
                    )
                    
                    (if (is-some new-description)
                        (map-set file-metadata
                            { file-identifier: file-identifier }
                            (merge file-record { content-description: (unwrap! new-description ERROR-INVALID-PARAMETERS) })
                        )
                        true
                    )
                    
                    (if (is-some new-category-tags)
                        (map-set file-categorization
                            { file-identifier: file-identifier }
                            { category-tags: (unwrap! new-category-tags ERROR-INVALID-PARAMETERS) }
                        )
                        true
                    )
                    
                    (ok true)
                )
            ERROR-FILE-NOT-FOUND
        )
    )
)

(define-read-only (get-version-history (file-identifier uint))
    (begin
        (try! (validate-file-identifier file-identifier))
        (try! (validate-file-exists file-identifier))
        (asserts! (has-read-access file-identifier tx-sender) ERROR-ACCESS-DENIED)
        (ok (map-get? file-modification-history { file-identifier: file-identifier, version-identifier: u1 }))
    )
)

(define-read-only (check-write-access (file-identifier uint) (account-principal principal))
    (begin
        (try! (validate-file-identifier file-identifier))
        (ok (has-write-access file-identifier account-principal))
    )
)

(define-read-only (get-file-info (file-identifier uint))
    (begin
        (try! (validate-file-identifier file-identifier))
        (try! (validate-file-exists file-identifier))
        (asserts! (has-read-access file-identifier tx-sender) ERROR-ACCESS-DENIED)
        (ok (map-get? file-metadata { file-identifier: file-identifier }))
    )
)

(define-read-only (get-storage-metrics (account-principal principal))
    (begin
        (try! (validate-user-account account-principal))
        (ok (default-to
            { total-file-count: u0, total-storage-bytes: u0, last-activity-timestamp: u0 }
            (map-get? user-storage-metrics { account-owner: account-principal })
        ))
    )
)