;; Clarity Collateral: SIP-009 NFT-Backed Dynamic Lending Protocol

;; Constants

;; Error codes
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-NFT-NOT-FOUND (err u101))
(define-constant ERR-NFT-ALREADY-LISTED (err u102))
(define-constant ERR-NFT-NOT-LISTED (err u103))
(define-constant ERR-LOAN-VALUE-INSUFFICIENT (err u104))
(define-constant ERR-LOAN-NOT-FOUND (err u105))
(define-constant ERR-LOAN-DEFAULTED (err u106))
(define-constant ERR-LOAN-REPAYMENT-NOT-DUE (err u107))
(define-constant ERR-LOAN-ALREADY-CLOSED (err u108))
(define-constant ERR-PAYMENT-TRANSACTION-FAILED (err u109))
(define-constant ERR-NFT-ATTRIBUTE-UPDATE-FAILED (err u110))
(define-constant ERR-INVALID-PRINCIPAL (err u111))
(define-constant ERR-INVALID-LOAN-AMOUNT (err u112))
(define-constant ERR-INVALID-LOAN-TERM (err u113))
(define-constant ERR-INVALID-INTEREST-RATE (err u114))
(define-constant ERR-INVALID-URI (err u115))

;; Loan status constants
(define-constant loan-status-active u1)
(define-constant loan-status-completed u2)
(define-constant loan-status-defaulted u3)

;; Validation constants
(define-constant MIN-LOAN-AMOUNT u1000)
(define-constant MAX-LOAN-AMOUNT u1000000000)
(define-constant MIN-LOAN-TERM u144) ;; Minimum 1 day (assuming ~10 min blocks)
(define-constant MAX-LOAN-TERM u52560) ;; Maximum ~1 year
(define-constant MAX-INTEREST-RATE u100) ;; Maximum 100% interest

;; Admin settings
(define-constant contract-administrator tx-sender)

;; Token Implementation

;; SIP-009 NFT Implementation
(define-non-fungible-token dynamic-credit-nft uint)

;; Data Maps

;; NFT attributes storage
(define-map nft-attribute-record
    { token-id: uint }
    {
        rarity-score: uint,
        power-level-score: uint,
        physical-condition: uint,
        credit-score: uint,
        last-attribute-update: uint
    }
)

;; Loan details storage
(define-map active-loan-registry
    { loan-id: uint }
    {
        borrower-address: principal,
        lender-address: principal,
        collateral-token-id: uint,
        loan-principal-amount: uint,
        annual-interest-rate: uint,
        loan-duration-blocks: uint,
        loan-start-block: uint,
        loan-status: uint,
        payment-delinquencies: uint,
        total-amount-repaid: uint
    }
)

;; Mapping from token to loan
(define-map nft-loan-registry 
    { token-id: uint }
    { loan-id: uint }
)

;; Available loan listings
(define-map available-loan-listings
    { token-id: uint }
    {
        nft-owner: principal,
        loan-amount-requested: uint,
        minimum-loan-duration: uint,
        maximum-interest-rate: uint
    }
)

;; Variables

(define-data-var nft-counter uint u1)
(define-data-var loan-counter uint u1)
(define-data-var metadata-base-uri (string-ascii 256) "https://clarity-collateral.io/metadata/")

;; Validation Functions

;; Validate principal is not the zero address
(define-private (is-valid-principal (address principal))
    (not (is-eq address 'SP000000000000000000002Q6VF78)))

;; Validate loan amount is within acceptable range
(define-private (is-valid-loan-amount (amount uint))
    (and (>= amount MIN-LOAN-AMOUNT) (<= amount MAX-LOAN-AMOUNT)))

;; Validate loan term is within acceptable range
(define-private (is-valid-loan-term (term uint))
    (and (>= term MIN-LOAN-TERM) (<= term MAX-LOAN-TERM)))

;; Validate interest rate is within acceptable range
(define-private (is-valid-interest-rate (rate uint))
    (<= rate MAX-INTEREST-RATE))

;; Validate URI is not empty and has proper format
(define-private (is-valid-uri (uri (string-ascii 256)))
    (and 
        (> (len uri) u0)
        ;; Check if length is at least 8 (length of "https://")
        (>= (len uri) u8)
    ))

;; SIP-009 NFT Standard Functions

(define-read-only (get-last-token-id)
    (- (var-get nft-counter) u1)
)

(define-read-only (get-token-uri (token-id uint))
    (ok (some (concat (var-get metadata-base-uri) (convert-uint-to-string token-id))))
)

(define-read-only (get-owner (token-id uint))
    (ok (nft-get-owner? dynamic-credit-nft token-id))
)

;; Read-only Functions

(define-read-only (get-nft-attributes (token-id uint))
    (map-get? nft-attribute-record { token-id: token-id })
)

(define-read-only (get-loan-information (loan-id uint))
    (map-get? active-loan-registry { loan-id: loan-id })
)

(define-read-only (get-nft-linked-loan (token-id uint))
    (map-get? nft-loan-registry { token-id: token-id })
)

(define-read-only (get-available-loan-listing (token-id uint))
    (map-get? available-loan-listings { token-id: token-id })
)

(define-read-only (calculate-total-loan-repayment (loan-id uint))
    (match (get-loan-information loan-id)
        loan-data
            (let
                ((total-with-interest (* (get loan-principal-amount loan-data) (+ u100 (get annual-interest-rate loan-data)))))
                (ok (/ total-with-interest u100)))
        (err ERR-LOAN-NOT-FOUND)
    )
)

(define-read-only (calculate-current-payment-due (loan-id uint))
    (match (get-loan-information loan-id)
        loan-data
            (let
                ((total-with-interest (* (get loan-principal-amount loan-data) (+ u100 (get annual-interest-rate loan-data))))
                 (payment-per-block (/ total-with-interest (get loan-duration-blocks loan-data)))
                 (current-block block-height)
                 (blocks-since-start (- current-block (get loan-start-block loan-data)))
                 (expected-payment-total (* payment-per-block blocks-since-start))
                 (actual-payment-total (get total-amount-repaid loan-data))
                 (current-payment-due (if (> expected-payment-total actual-payment-total)
                                 (- expected-payment-total actual-payment-total)
                                 u0)))
                (ok current-payment-due))
        (err ERR-LOAN-NOT-FOUND)
    )
)

;; NFT Mint & Management Functions

;; Mint new NFT
(define-public (mint-credit-nft (recipient-address principal))
    (let 
        ((new-token-id (var-get nft-counter)))
        
        ;; Validate recipient address
        (asserts! (is-valid-principal recipient-address) ERR-INVALID-PRINCIPAL)

        ;; Mint NFT
        (try! (nft-mint? dynamic-credit-nft new-token-id recipient-address))

        ;; Set initial attributes
        (map-set nft-attribute-record
            { token-id: new-token-id }
            {
                rarity-score: u70,
                power-level-score: u70,
                physical-condition: u100,
                credit-score: u50,
                last-attribute-update: block-height
            }
        )

        ;; Increment token ID
        (var-set nft-counter (+ new-token-id u1))
        (ok new-token-id)
    )
)

;; Loan Listing Functions

;; List NFT for loan
(define-public (create-loan-listing 
    (token-id uint) 
    (requested-loan-amount uint)
    (minimum-loan-term uint)
    (maximum-interest-rate uint))

    (let ((token-owner (unwrap! (nft-get-owner? dynamic-credit-nft token-id) ERR-NFT-NOT-FOUND)))
        ;; Checks
        (asserts! (is-eq tx-sender token-owner) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (is-none (get-available-loan-listing token-id)) ERR-NFT-ALREADY-LISTED)
        (asserts! (is-none (get-nft-linked-loan token-id)) ERR-NFT-ALREADY-LISTED)
        
        ;; Validate loan parameters
        (asserts! (is-valid-loan-amount requested-loan-amount) ERR-INVALID-LOAN-AMOUNT)
        (asserts! (is-valid-loan-term minimum-loan-term) ERR-INVALID-LOAN-TERM)
        (asserts! (is-valid-interest-rate maximum-interest-rate) ERR-INVALID-INTEREST-RATE)

        ;; Create listing
        (map-set available-loan-listings
            { token-id: token-id }
            {
                nft-owner: tx-sender,
                loan-amount-requested: requested-loan-amount,
                minimum-loan-duration: minimum-loan-term,
                maximum-interest-rate: maximum-interest-rate
            }
        )
        (ok true)
    )
)

;; Cancel loan listing
(define-public (remove-loan-listing (token-id uint))
    (let ((listing (unwrap! (get-available-loan-listing token-id) ERR-NFT-NOT-LISTED)))
        ;; Check owner
        (asserts! (is-eq tx-sender (get nft-owner listing)) ERR-UNAUTHORIZED-ACCESS)
        
        ;; Remove listing
        (map-delete available-loan-listings { token-id: token-id })
        (ok true)
    )
)

;; Loan Management Functions

;; Offer loan
(define-public (fund-loan-request 
    (token-id uint)
    (loan-amount uint)
    (interest-rate-offered uint)
    (loan-duration-offered uint))

    (let 
        ((listing (unwrap! (get-available-loan-listing token-id) ERR-NFT-NOT-LISTED))
         (new-loan-id (var-get loan-counter)))

        ;; Validate loan parameters
        (asserts! (is-valid-loan-amount loan-amount) ERR-INVALID-LOAN-AMOUNT)
        (asserts! (is-valid-loan-term loan-duration-offered) ERR-INVALID-LOAN-TERM)
        (asserts! (is-valid-interest-rate interest-rate-offered) ERR-INVALID-INTEREST-RATE)

        ;; Checks against listing requirements
        (asserts! (>= loan-amount (get loan-amount-requested listing)) ERR-LOAN-VALUE-INSUFFICIENT)
        (asserts! (>= loan-duration-offered (get minimum-loan-duration listing)) ERR-LOAN-VALUE-INSUFFICIENT)
        (asserts! (<= interest-rate-offered (get maximum-interest-rate listing)) ERR-LOAN-VALUE-INSUFFICIENT)

        ;; Transfer STX to borrower
        (try! (stx-transfer? loan-amount tx-sender (get nft-owner listing)))

        ;; Create loan
        (map-set active-loan-registry
            { loan-id: new-loan-id }
            {
                borrower-address: (get nft-owner listing),
                lender-address: tx-sender,
                collateral-token-id: token-id,
                loan-principal-amount: loan-amount,
                annual-interest-rate: interest-rate-offered,
                loan-duration-blocks: loan-duration-offered,
                loan-start-block: block-height,
                loan-status: loan-status-active,
                payment-delinquencies: u0,
                total-amount-repaid: u0
            }
        )

        ;; Link token to loan
        (map-set nft-loan-registry { token-id: token-id } { loan-id: new-loan-id })

        ;; Remove listing
        (map-delete available-loan-listings { token-id: token-id })

        ;; Transfer NFT to contract
        (try! (nft-transfer? dynamic-credit-nft token-id (get nft-owner listing) (as-contract tx-sender)))

        ;; Increment loan ID
        (var-set loan-counter (+ new-loan-id u1))
        (ok new-loan-id)
    )
)

;; Make loan payment
(define-public (submit-loan-payment (loan-id uint) (payment-amount uint))
    (let
        ((loan-record (unwrap! (get-loan-information loan-id) ERR-LOAN-NOT-FOUND))
         (current-due-amount (unwrap! (calculate-current-payment-due loan-id) ERR-LOAN-NOT-FOUND)))

        ;; Checks
        (asserts! (is-eq (get loan-status loan-record) loan-status-active) ERR-LOAN-ALREADY-CLOSED)
        (asserts! (is-eq tx-sender (get borrower-address loan-record)) ERR-UNAUTHORIZED-ACCESS)
        
        ;; Transfer STX from borrower to lender
        (try! (stx-transfer? payment-amount tx-sender (get lender-address loan-record)))

        ;; Update loan details
        (map-set active-loan-registry
            { loan-id: loan-id }
            (merge loan-record {
                total-amount-repaid: (+ (get total-amount-repaid loan-record) payment-amount),
                payment-delinquencies: (if (>= payment-amount current-due-amount)
                                    u0
                                    (+ (get payment-delinquencies loan-record) u1))
            })
        )

        ;; Update NFT attributes based on payment
        (update-nft-credit-attributes-handler loan-id payment-amount current-due-amount)
        (ok true)
    )
)

;; Close loan
(define-public (finalize-loan (loan-id uint))
    (let
        ((loan-record (unwrap! (get-loan-information loan-id) ERR-LOAN-NOT-FOUND))
         (total-amount-due (unwrap! (calculate-total-loan-repayment loan-id) ERR-LOAN-NOT-FOUND)))

        ;; Checks
        (asserts! (is-eq (get loan-status loan-record) loan-status-active) ERR-LOAN-ALREADY-CLOSED)
        (asserts! (>= (- block-height (get loan-start-block loan-record)) (get loan-duration-blocks loan-record)) ERR-LOAN-REPAYMENT-NOT-DUE)

        (if (>= (get total-amount-repaid loan-record) total-amount-due)
            ;; Loan successfully repaid - return the NFT and complete the loan
            (let
                ;; Return NFT to borrower
                ((nft-transfer-result (as-contract (nft-transfer? 
                    dynamic-credit-nft 
                    (get collateral-token-id loan-record) 
                    (as-contract tx-sender) 
                    (get borrower-address loan-record)))))
                
                ;; Check NFT transfer status
                (match nft-transfer-result
                    success
                        (begin
                            ;; Update loan status
                            (map-set active-loan-registry
                                { loan-id: loan-id }
                                (merge loan-record { loan-status: loan-status-completed }))
                            
                            ;; Remove token-loan association
                            (map-delete nft-loan-registry { token-id: (get collateral-token-id loan-record) })
                            
                            ;; Improve NFT's rarity on successful completion
                            (boost-nft-rarity-score-handler (get collateral-token-id loan-record) u5)
                            (ok true)
                        )
                    error (err error)
                )
            )

            ;; Loan defaulted - transfer NFT to lender
            (let
                ;; Transfer NFT to lender
                ((nft-transfer-result (as-contract (nft-transfer? 
                    dynamic-credit-nft 
                    (get collateral-token-id loan-record) 
                    (as-contract tx-sender) 
                    (get lender-address loan-record)))))
                
                ;; Check NFT transfer status
                (match nft-transfer-result
                    success
                        (begin
                            ;; Update loan status
                            (map-set active-loan-registry
                                { loan-id: loan-id }
                                (merge loan-record { loan-status: loan-status-defaulted }))
                            
                            ;; Remove token-loan association
                            (map-delete nft-loan-registry { token-id: (get collateral-token-id loan-record) })
                            
                            ;; Penalize NFT's attributes for default
                            (penalize-nft-attributes-handler (get collateral-token-id loan-record))
                            (ok false)
                        )
                    error (err error)
                )
            )
        )
    )
)

;; Force close defaulted loan (can be triggered by lender)
(define-public (liquidate-defaulted-loan (loan-id uint))
    (let
        ((loan-record (unwrap! (get-loan-information loan-id) ERR-LOAN-NOT-FOUND)))

        ;; Checks
        (asserts! (is-eq (get loan-status loan-record) loan-status-active) ERR-LOAN-ALREADY-CLOSED)
        (asserts! (is-eq tx-sender (get lender-address loan-record)) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (>= (get payment-delinquencies loan-record) u3) ERR-LOAN-REPAYMENT-NOT-DUE)

        ;; Transfer NFT to lender
        (try! (as-contract (nft-transfer? 
            dynamic-credit-nft 
            (get collateral-token-id loan-record) 
            (as-contract tx-sender) 
            (get lender-address loan-record))))

        ;; Update loan status
        (map-set active-loan-registry
            { loan-id: loan-id }
            (merge loan-record { loan-status: loan-status-defaulted }))
        
        ;; Remove token-loan association
        (map-delete nft-loan-registry { token-id: (get collateral-token-id loan-record) })
        
        ;; Degrade NFT's attributes for forced closure
        (penalize-nft-attributes-handler (get collateral-token-id loan-record))
        (ok true)
    )
)

;; Helper Functions

(define-private (get-minimum-value (value-a uint) (value-b uint))
    (if (<= value-a value-b) value-a value-b)
)

(define-private (get-maximum-value (value-a uint) (value-b uint))
    (if (>= value-a value-b) value-a value-b)
)

;; Convert uint to string for URI (fixed implementation using if-else instead of cond)
(define-private (convert-uint-to-string (value uint))
  (let ((digit-map "0123456789"))
    ;; Special case for 0
    (if (is-eq value u0) 
      "0"
      ;; Single digit
      (if (< value u10)
        (unwrap-panic (element-at digit-map value))
        ;; Two digits
        (if (< value u100)
          (concat 
            (unwrap-panic (element-at digit-map (/ value u10)))
            (unwrap-panic (element-at digit-map (mod value u10))))
          ;; Three digits
          (if (< value u1000)
            (concat 
              (unwrap-panic (element-at digit-map (/ value u100)))
              (concat
                (unwrap-panic (element-at digit-map (mod (/ value u10) u10)))
                (unwrap-panic (element-at digit-map (mod value u10)))))
            ;; Four digits
            (if (< value u10000)
              (concat 
                (unwrap-panic (element-at digit-map (/ value u1000)))
                (concat
                  (unwrap-panic (element-at digit-map (mod (/ value u100) u10)))
                  (concat
                    (unwrap-panic (element-at digit-map (mod (/ value u10) u10)))
                    (unwrap-panic (element-at digit-map (mod value u10))))))
              ;; Five digits or larger (truncate to 5 digits for simplicity)
              (concat 
                (unwrap-panic (element-at digit-map (/ value u10000)))
                (concat
                  (unwrap-panic (element-at digit-map (mod (/ value u1000) u10)))
                  (concat
                    (unwrap-panic (element-at digit-map (mod (/ value u100) u10)))
                    (concat
                      (unwrap-panic (element-at digit-map (mod (/ value u10) u10)))
                      (unwrap-panic (element-at digit-map (mod value u10)))))))
            )
          )
        )
      )
    )
  )
)

;; NFT Attribute Management Functions

;; Modified version that doesn't return responses, called from public functions
(define-private (update-nft-credit-attributes-handler (loan-id uint) (payment-amount uint) (required-payment uint))
    (match (get-loan-information loan-id)
        loan-data (match (get-nft-attributes (get collateral-token-id loan-data))
            token-data (begin
                (map-set nft-attribute-record
                    { token-id: (get collateral-token-id loan-data) }
                    {
                        physical-condition: (if (>= payment-amount required-payment)
                            (get-minimum-value u100 (+ (get physical-condition token-data) u5))
                            (get-maximum-value u1 (- (get physical-condition token-data) u10))),
                        power-level-score: (if (>= payment-amount required-payment)
                            (get-minimum-value u100 (+ (get power-level-score token-data) u3))
                            (get-maximum-value u1 (- (get power-level-score token-data) u7))),
                        rarity-score: (get rarity-score token-data),
                        credit-score: (if (>= payment-amount required-payment)
                            (get-minimum-value u100 (+ (get credit-score token-data) u8))
                            (get-maximum-value u1 (- (get credit-score token-data) u15))),
                        last-attribute-update: block-height
                    }
                )
                true)
            false)
        false)
)

;; Original function kept for backwards compatibility
(define-private (update-nft-credit-attributes (loan-id uint) (payment-amount uint) (required-payment uint))
    (match (get-loan-information loan-id)
        loan-data (match (get-nft-attributes (get collateral-token-id loan-data))
            token-data (begin
                (map-set nft-attribute-record
                    { token-id: (get collateral-token-id loan-data) }
                    {
                        physical-condition: (if (>= payment-amount required-payment)
                            (get-minimum-value u100 (+ (get physical-condition token-data) u5))
                            (get-maximum-value u1 (- (get physical-condition token-data) u10))),
                        power-level-score: (if (>= payment-amount required-payment)
                            (get-minimum-value u100 (+ (get power-level-score token-data) u3))
                            (get-maximum-value u1 (- (get power-level-score token-data) u7))),
                        rarity-score: (get rarity-score token-data),
                        credit-score: (if (>= payment-amount required-payment)
                            (get-minimum-value u100 (+ (get credit-score token-data) u8))
                            (get-maximum-value u1 (- (get credit-score token-data) u15))),
                        last-attribute-update: block-height
                    }
                )
                (ok true))
            (err ERR-NFT-NOT-FOUND))
        (err ERR-LOAN-NOT-FOUND))
)

;; Handler function for boost-nft-rarity-score that doesn't return a response
(define-private (boost-nft-rarity-score-handler (token-id uint) (boost-amount uint))
    (match (get-nft-attributes token-id)
        token-data (begin
            (map-set nft-attribute-record
                { token-id: token-id }
                (merge token-data {
                    rarity-score: (get-minimum-value u100 (+ (get rarity-score token-data) boost-amount)),
                    last-attribute-update: block-height
                })
            )
            true)
        false)
)

;; Original function kept for backwards compatibility
(define-private (boost-nft-rarity-score (token-id uint) (boost-amount uint))
    (match (get-nft-attributes token-id)
        token-data (begin
            (map-set nft-attribute-record
                { token-id: token-id }
                (merge token-data {
                    rarity-score: (get-minimum-value u100 (+ (get rarity-score token-data) boost-amount)),
                    last-attribute-update: block-height
                })
            )
            (ok true))
        (err ERR-NFT-NOT-FOUND))
)

;; Handler function for penalize-nft-attributes that doesn't return a response
(define-private (penalize-nft-attributes-handler (token-id uint))
    (match (get-nft-attributes token-id)
        token-data (begin
            (map-set nft-attribute-record
                { token-id: token-id }
                {
                    rarity-score: (get-maximum-value u1 (- (get rarity-score token-data) u10)),
                    power-level-score: (get-maximum-value u1 (- (get power-level-score token-data) u15)),
                    physical-condition: (get-maximum-value u1 (- (get physical-condition token-data) u20)),
                    credit-score: (get-maximum-value u1 (- (get credit-score token-data) u25)),
                    last-attribute-update: block-height
                }
            )
            true)
        false)
)

;; Original function kept for backwards compatibility
(define-private (penalize-nft-attributes (token-id uint))
    (match (get-nft-attributes token-id)
        token-data (begin
            (map-set nft-attribute-record
                { token-id: token-id }
                {
                    rarity-score: (get-maximum-value u1 (- (get rarity-score token-data) u10)),
                    power-level-score: (get-maximum-value u1 (- (get power-level-score token-data) u15)),
                    physical-condition: (get-maximum-value u1 (- (get physical-condition token-data) u20)),
                    credit-score: (get-maximum-value u1 (- (get credit-score token-data) u25)),
                    last-attribute-update: block-height
                }
            )
            (ok true))
        (err ERR-NFT-NOT-FOUND))
)

;; Administrative Functions

;; Set token URI base (admin only)
(define-public (update-metadata-base-uri (new-uri (string-ascii 256)))
    (begin
        (asserts! (is-eq tx-sender contract-administrator) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (is-valid-uri new-uri) ERR-INVALID-URI)
        (var-set metadata-base-uri new-uri)
        (ok true)
    )
)