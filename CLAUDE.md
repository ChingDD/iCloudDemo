# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an iOS demo application showcasing CloudKit integration for data synchronization with iCloud. The app demonstrates basic CRUD operations with cloud storage using Apple's CloudKit framework.

## Architecture

- **CloudeSyncMgr.swift**: Singleton manager class handling CloudKit operations
  - Manages CKContainer.default() for cloud operations
  - Handles save and delete operations to CloudKit
  - Uses background queues for cloud operations
  - Implements shared zones for data sharing

- **ViewController.swift**: Main table view controller
  - Displays a list of data items
  - Provides navigation to AddViewController for creating/editing items
  - Uses CloudeSyncMgr for cloud operations

- **AddViewController.swift**: Form view controller for adding/editing items
  - Simple text input interface with confirmation button
  - Handles user input for data creation/modification

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
- Implements singleton pattern for cloud manager
- Uses delegation pattern for table view management
- Background queue usage for cloud operations
- Target-action pattern for UI interactions

## Development Notes

- The project uses Xcode 16.1 with modern Swift features
- CloudKit operations run on background queues to avoid blocking the main thread
- The app requires proper iCloud entitlements and Apple Developer account setup for cloud functionality to work