# Release Checklist

## Pre-Release Verification

### Automated Checks
- [ ] Run `flutter test` - All tests pass
- [ ] Run `flutter analyze` - Zero warnings/errors
- [ ] Run CI pipeline - All jobs pass
- [ ] Verify APK builds successfully on Android
- [ ] Verify Linux build completes without errors

### Manual Testing
- [ ] **Smoke Test on Linux**: Open app, create tab, type basic commands, verify output
- [ ] **Health Check**: Open Settings > Diagnostics, verify all services show green status
- [ ] **Feature Verification**:
  - [ ] Terminal core functionality works
  - [ ] Tab creation/closing works
  - [ ] Settings panel opens
  - [ ] FPS counter toggles
  - [ ] Error handling shows user-friendly dialogs

### Performance Validation
- [ ] Frame times stay under 16ms during normal operation
- [ ] Memory usage doesn't grow unbounded during extended use
- [ ] App remains responsive during heavy operations

### Compatibility Checks
- [ ] Test on minimum supported Flutter version (3.22.0)
- [ ] Verify with different screen sizes/resolutions
- [ ] Test with various system themes

## Build Process
- [ ] Create release build: `flutter build linux --release`
- [ ] Create Android APK: `flutter build apk --release`
- [ ] Verify builds complete without warnings
- [ ] Test release builds on target platforms

## Final Sign-off
- [ ] Code review completed
- [ ] All automated tests pass
- [ ] Manual testing completed
- [ ] Performance benchmarks met
- [ ] No critical issues in issue tracker
- [ ] Release notes updated