# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an iOS demo application showcasing CloudKit integration for data synchronization with iCloud. The app demonstrates basic CRUD operations with cloud storage using Apple's CloudKit framework.

## Architecture

- **Item.swift**: Data model structure
  - Contains title (String), isShare (Bool), timestamp (Double) properties
  - Timestamp used as unique identifier for cloud record matching

- **CloudSyncMgr.swift**: Singleton manager class handling CloudKit operations
  - Manages CKContainer with identifier "iCloud.com.jeff.iCloudDemo"
  - `fetchRecords()`: Retrieves all records from cloud and converts to Item array
  - `saveToCloud(item:)`: Creates new cloud records for new items
  - `updateToCloud(item:)`: Updates existing cloud records based on timestamp matching
  - Uses background queues for cloud operations
  - Handles CloudKit record conversion with proper data type mapping

- **ViewController.swift**: Main table view controller
  - Displays list of items fetched from CloudKit on app launch
  - Implements AddViewControllerDelegate for handling add/edit operations
  - Provides navigation to AddViewController for creating/editing items
  - Supports swipe-to-delete functionality

- **AddViewController.swift**: Form view controller for adding/editing items
  - Text input field and share toggle button interface
  - `configForEdit()`: Configures view for editing existing items with pre-filled data
  - `configForAdd()`: Configures view for adding new items
  - Uses currentItem property to maintain item state
  - Calls appropriate CloudSyncMgr methods (save vs update) based on editing mode

## Development Commands

### Building and Running
```bash
# Build the project
xcodebuild -project iCloudDemo.xcodeproj -scheme iCloudDemo -configuration Debug build

# Build and run on simulator
xcodebuild -project iCloudDemo.xcodeproj -scheme iCloudDemo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 15' build

# Open in Xcode
open iCloudDemo.xcodeproj
```

### Testing
```bash
# Run tests (if available)
xcodebuild -project iCloudDemo.xcodeproj -scheme iCloudDemo -destination 'platform=iOS Simulator,name=iPhone 15' test
```

## Important Configuration

- **Bundle Identifier**: com.jeff.iCloudDemo
- **Deployment Target**: iOS 18.1
- **Swift Version**: 5.0
- **Development Team**: WY78FBFM76

### iCloud Configuration
The app is configured with the following iCloud capabilities (in iCloudDemo.entitlements):
- CloudDocuments and CloudKit services enabled
- Container identifier: iCloud.com.jeff.iCloudDemo
- Push notifications environment: development

## Code Patterns

- Uses programmatic UI (no Storyboard dependencies beyond launch)
- Implements singleton pattern for cloud manager (CloudSyncMgr.shared)
- Uses delegation pattern for data flow between view controllers (AddViewControllerDelegate)
- Configuration-before-presentation pattern for view controller setup
- Timestamp-based record identification for cloud updates
- Background queue usage for cloud operations
- Target-action pattern for UI interactions

## Development Notes

- The project uses Xcode 16.1 with modern Swift features
- CloudKit operations run on background queues to avoid blocking the main thread
- The app requires proper iCloud entitlements and Apple Developer account setup for cloud functionality to work