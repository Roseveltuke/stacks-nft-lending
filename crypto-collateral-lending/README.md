# Clarity Collateral: SIP-009 NFT-Backed Dynamic Lending Protocol

A decentralized lending protocol on Stacks that enables NFT holders to use their digital assets as collateral for cryptocurrency loans.

## Overview

Clarity Collateral is a smart contract protocol built on Stacks that implements NFT-backed loans. It allows NFT holders to use their digital assets as collateral to obtain STX token loans, creating liquidity for otherwise illiquid NFT assets. The protocol features dynamic NFT attributes that change based on the borrower's repayment behavior, creating a credit scoring system within the NFT ecosystem.

## Features

- **SIP-009 Compliant NFTs**: Implements the standard Stacks NFT interface
- **Dynamic NFT Attributes**: NFT properties change based on loan repayment behavior
- **Credit Scoring System**: NFTs develop a "credit history" based on loan performance
- **Flexible Loan Terms**: Customizable loan amounts, durations, and interest rates
- **Peer-to-Peer Lending**: Direct borrower to lender matching
- **Automatic Collateral Management**: Secure collateral handling and liquidation process
- **Loan Lifecycle Management**: Full support for loan creation, repayment, and closure

## Technical Architecture

The protocol is built as a single Clarity smart contract with the following key components:

1. **NFT Implementation**: A SIP-009 compliant non-fungible token implementation
2. **Data Storage**: Maps for tracking NFT attributes, loan details, and listings
3. **Lending Logic**: Functions for loan creation, repayment, and liquidation
4. **Attribute System**: Mechanism for updating NFT properties based on loan performance

## Key Components

The protocol consists of several interconnected data structures:

- **NFT Attribute Record**: Stores the dynamic properties of each NFT
- **Active Loan Registry**: Maintains details of all active loans
- **NFT Loan Registry**: Maps NFTs to their associated loans
- **Available Loan Listings**: Tracks NFTs available for loans

## How It Works

### For Borrowers:

1. **Mint or Deposit NFT**: Obtain an NFT within the protocol
2. **Create Loan Listing**: Specify desired loan terms
3. **Receive Loan**: When a lender accepts the terms, STX tokens are transferred
4. **Make Repayments**: Pay back the loan to improve NFT attributes
5. **Reclaim NFT**: Successfully repaid loans return the NFT with improved attributes

### For Lenders:

1. **Browse Listings**: View available NFTs offered as collateral
2. **Fund Loan**: Send STX tokens to borrower when accepting a loan request
3. **Collect Repayments**: Receive principal plus interest when borrower repays
4. **Liquidation**: Claim the NFT collateral if the borrower defaults

## Functions Reference

### NFT Management

#### `mint-credit-nft`
Creates a new NFT with default attributes and assigns it to the specified address.

```
(define-public (mint-credit-nft (recipient-address principal))
```

Parameters:
- `recipient-address`: The address to receive the newly minted NFT

Returns:
- `(ok uint)`: The ID of the newly minted NFT
- `(err uint)`: Error code if the operation fails

### Loan Listings

#### `create-loan-listing`
Lists an NFT as available collateral for a loan with specified terms.

```
(define-public (create-loan-listing 
    (token-id uint) 
    (requested-loan-amount uint)
    (minimum-loan-term uint)
    (maximum-interest-rate uint))
```

Parameters:
- `token-id`: The ID of the NFT to use as collateral
- `requested-loan-amount`: The amount of STX tokens requested
- `minimum-loan-term`: The minimum acceptable loan duration in blocks
- `maximum-interest-rate`: The maximum acceptable annual interest rate

Returns:
- `(ok bool)`: True if listing created successfully
- `(err uint)`: Error code if the operation fails

#### `remove-loan-listing`
Cancels an active loan listing.

```
(define-public (remove-loan-listing (token-id uint))
```

Parameters:
- `token-id`: The ID of the NFT to remove from listings

Returns:
- `(ok bool)`: True if listing removed successfully
- `(err uint)`: Error code if the operation fails

### Loan Management

#### `fund-loan-request`
Accepts a loan listing and transfers funds to the borrower.

```
(define-public (fund-loan-request 
    (token-id uint)
    (loan-amount uint)
    (interest-rate-offered uint)
    (loan-duration-offered uint))
```

Parameters:
- `token-id`: The ID of the NFT from the loan listing
- `loan-amount`: The amount of STX tokens to lend
- `interest-rate-offered`: The annual interest rate being offered
- `loan-duration-offered`: The loan duration in blocks

Returns:
- `(ok uint)`: The ID of the newly created loan
- `(err uint)`: Error code if the operation fails

#### `submit-loan-payment`
Makes a payment toward an active loan.

```
(define-public (submit-loan-payment (loan-id uint) (payment-amount uint))
```

Parameters:
- `loan-id`: The ID of the loan to make a payment on
- `payment-amount`: The amount of STX tokens to pay

Returns:
- `(ok bool)`: True if payment processed successfully
- `(err uint)`: Error code if the operation fails

#### `finalize-loan`
Closes a loan after the term has expired, either returning the NFT to the borrower (if fully repaid) or transferring it to the lender (if defaulted).

```
(define-public (finalize-loan (loan-id uint))
```

Parameters:
- `loan-id`: The ID of the loan to finalize

Returns:
- `(ok bool)`: True if the loan was successfully repaid, false if it defaulted
- `(err uint)`: Error code if the operation fails

#### `liquidate-defaulted-loan`
Forces closure of a loan with multiple missed payments.

```
(define-public (liquidate-defaulted-loan (loan-id uint))
```

Parameters:
- `loan-id`: The ID of the loan to liquidate

Returns:
- `(ok bool)`: True if the loan was successfully liquidated
- `(err uint)`: Error code if the operation fails

### Read-Only Functions

#### `get-nft-attributes`
Retrieves the current attributes of an NFT.

```
(define-read-only (get-nft-attributes (token-id uint))
```

#### `get-loan-information`
Retrieves detailed information about a loan.

```
(define-read-only (get-loan-information (loan-id uint))
```

#### `calculate-total-loan-repayment`
Calculates the total amount due for a loan including interest.

```
(define-read-only (calculate-total-loan-repayment (loan-id uint))
```

#### `calculate-current-payment-due`
Calculates the current amount due for a loan based on elapsed time.

```
(define-read-only (calculate-current-payment-due (loan-id uint))
```

### Administrative Functions

#### `update-metadata-base-uri`
Updates the base URI for NFT metadata (admin only).

```
(define-public (update-metadata-base-uri (new-uri (string-ascii 256)))
```

## Error Codes

The protocol defines several error codes for different failure scenarios:

- `ERR-UNAUTHORIZED-ACCESS (u100)`: Operation attempted by unauthorized principal
- `ERR-NFT-NOT-FOUND (u101)`: Referenced NFT does not exist
- `ERR-NFT-ALREADY-LISTED (u102)`: NFT is already listed or has an active loan
- `ERR-NFT-NOT-LISTED (u103)`: NFT is not listed for a loan
- `ERR-LOAN-VALUE-INSUFFICIENT (u104)`: Offered loan terms do not meet minimum requirements
- `ERR-LOAN-NOT-FOUND (u105)`: Referenced loan does not exist
- `ERR-LOAN-DEFAULTED (u106)`: Loan is in defaulted state
- `ERR-LOAN-REPAYMENT-NOT-DUE (u107)`: Attempted to finalize a loan before its term
- `ERR-LOAN-ALREADY-CLOSED (u108)`: Loan is already closed
- `ERR-PAYMENT-TRANSACTION-FAILED (u109)`: STX transfer failed
- `ERR-NFT-ATTRIBUTE-UPDATE-FAILED (u110)`: Failed to update NFT attributes
- `ERR-INVALID-PRINCIPAL (u111)`: Invalid principal address provided
- `ERR-INVALID-LOAN-AMOUNT (u112)`: Loan amount outside acceptable range
- `ERR-INVALID-LOAN-TERM (u113)`: Loan term outside acceptable range
- `ERR-INVALID-INTEREST-RATE (u114)`: Interest rate outside acceptable range
- `ERR-INVALID-URI (u115)`: Invalid metadata URI format

## Constants and Limitations

The protocol enforces several limits:

- Minimum loan amount: 1,000 STX
- Maximum loan amount: 1,000,000,000 STX
- Minimum loan term: 144 blocks (~1 day at 10 min/block)
- Maximum loan term: 52,560 blocks (~1 year at 10 min/block)
- Maximum interest rate: 100%

## Getting Started

### Prerequisites

- Stacks blockchain node
- Clarity development environment (Clarinet recommended)

### Installation

1. Clone the repository
2. Set up a local Stacks development environment using Clarinet
3. Deploy the contract to your local test environment

### Basic Usage Example

```clarity
;; Mint a new NFT
(contract-call? .clarity-collateral mint-credit-nft 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)

;; Create a loan listing
(contract-call? .clarity-collateral create-loan-listing u1 u10000 u1440 u10)

;; Fund a loan
(contract-call? .clarity-collateral fund-loan-request u1 u10000 u5 u2000)

;; Make a payment
(contract-call? .clarity-collateral submit-loan-payment u1 u2000)

;; Close a loan
(contract-call? .clarity-collateral finalize-loan u1)
```

## Development and Testing

### Running Tests

1. Install Clarinet: `curl -sSL https://get.clarinet.co | bash`
2. Run tests: `clarinet test`

### Deploying to Testnet

1. Configure your Stacks testnet account
2. Deploy using Clarinet: `clarinet deploy --testnet`

## Security Considerations

- **Collateral Valuation**: The protocol does not attempt to price NFTs; lenders must determine value
- **Interest Rate Risk**: Fixed rates for the full loan term
- **Smart Contract Risk**: Always audit contracts before use with significant funds
- **Liquidation Risk**: Defaulted loans transfer NFT ownership to lenders without auction process