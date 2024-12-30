# File Sharing Smart Contract

## Overview
This smart contract implements a decentralized file sharing system on the Stacks blockchain. It enables users to upload, manage, and share files with granular access controls, version tracking, and storage management.

## Features
- File upload and management
- Version control and history tracking
- Granular access permissions with expiration dates
- File metadata management
- Storage quota management
- File categorization with tags
- Public/private file visibility
- Support for encrypted files

## Technical Specifications

### Storage Limits
- Maximum file size: 1GB (1,073,741,824 bytes)
- Maximum files per user: 100
- Maximum tags per file: 10
- File name maximum length: 64 characters
- File description maximum length: 256 characters
- File type/MIME type maximum length: 32 characters

### Data Structures

#### File Metadata
Stores core information about each file:
```clarity
{
    file-owner: principal,
    file-display-name: string-ascii,
    content-hash: string-ascii,
    content-size-bytes: uint,
    creation-timestamp: uint,
    modification-timestamp: uint,
    content-mime-type: string-ascii,
    content-description: string-ascii,
    visibility-private: bool,
    encryption-enabled: bool,
    current-version: uint
}
```

#### File Permissions
Manages access control for shared files:
```clarity
{
    read-permission: bool,
    write-permission: bool,
    permission-grant-date: uint,
    permission-expiry-date: optional uint
}
```

#### Storage Metrics
Tracks user storage usage:
```clarity
{
    total-file-count: uint,
    total-storage-bytes: uint,
    last-activity-timestamp: uint
}
```

## Public Functions

### File Management

#### `upload-file`
Upload a new file to the system.
```clarity
(upload-file 
    file-display-name: string-ascii,
    content-hash: string-ascii,
    content-size-bytes: uint,
    content-mime-type: string-ascii,
    content-description: string-ascii,
    visibility-private: bool,
    encryption-enabled: bool,
    category-tags: list
) -> response
```

#### `update-file`
Update an existing file with new content.
```clarity
(update-file 
    file-identifier: uint,
    updated-content-hash: string-ascii,
    updated-size-bytes: uint,
    modification-notes: string-ascii
) -> response
```

#### `update-metadata`
Update file metadata without changing content.
```clarity
(update-metadata
    file-identifier: uint,
    new-display-name: optional string-ascii,
    new-description: optional string-ascii,
    new-category-tags: optional list
) -> response
```

### Access Control

#### `grant-access`
Grant file access permissions to another user.
```clarity
(grant-access 
    file-identifier: uint,
    authorized-user: principal,
    write-permission: bool,
    permission-expiry-date: optional uint
) -> response
```

### Read-Only Functions

#### `get-version-history`
Retrieve version history for a file.
```clarity
(get-version-history file-identifier: uint) -> response
```

#### `check-write-access`
Check if a user has write permissions for a file.
```clarity
(check-write-access file-identifier: uint, account-principal: principal) -> response
```

#### `get-file-info`
Retrieve detailed information about a file.
```clarity
(get-file-info file-identifier: uint) -> response
```

#### `get-storage-metrics`
Get storage usage statistics for a user.
```clarity
(get-storage-metrics account-principal: principal) -> response
```

## Error Codes
- `ERROR-ADMIN-ONLY` (u100): Operation restricted to contract administrator
- `ERROR-FILE-NOT-FOUND` (u101): Requested file does not exist
- `ERROR-ACCESS-DENIED` (u102): User lacks required permissions
- `ERROR-INVALID-PARAMETERS` (u103): Invalid input parameters
- `ERROR-DUPLICATE-FILE` (u104): File already exists
- `ERROR-STORAGE-EXCEEDED` (u105): User storage quota exceeded

## Usage Examples

### Uploading a New File
```clarity
(contract-call? .file-sharing upload-file 
    "example.txt"                  ;; file name
    "hash123..."                   ;; content hash
    u1000                         ;; file size in bytes
    "text/plain"                  ;; mime type
    "Example text file"           ;; description
    true                         ;; private
    false                        ;; not encrypted
    (list "document" "text")     ;; tags
)
```

### Granting Access to Another User
```clarity
(contract-call? .file-sharing grant-access
    u1                           ;; file ID
    'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM  ;; user to grant access
    false                        ;; read-only access
    (some u144)                 ;; expires in 144 blocks
)
```

## Security Considerations
1. All file content is stored off-chain; only metadata and access controls are managed by the contract
2. File hashes should be verified off-chain to ensure content integrity
3. For private files, content should be encrypted before uploading
4. Access expiration dates should be set appropriately for sensitive files
5. Users should monitor their storage quotas to prevent reaching limits