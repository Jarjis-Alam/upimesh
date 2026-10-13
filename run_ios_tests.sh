#!/usr/bin/env bash
set -e

echo "=== Building and Running iOS Offline Payment & Transport Tests (Stage 6.1 - 6.4B) ==="

swiftc -framework Foundation -framework Security -framework CryptoKit \
  ios/UPIMesh/UPIMesh/PaymentInstruction.swift \
  ios/UPIMesh/UPIMesh/DeviceIdentityManager.swift \
  ios/UPIMesh/UPIMesh/OfflinePaymentPacket.swift \
  ios/UPIMesh/UPIMesh/OfflinePacketStore.swift \
  ios/UPIMesh/UPIMesh/OfflinePaymentService.swift \
  ios/UPIMesh/UPIMesh/OfflinePaymentPacketTests.swift \
  ios/UPIMesh/UPIMesh/ReceivedPacketStore.swift \
  ios/UPIMesh/UPIMesh/PeerTransferMessage.swift \
  ios/UPIMesh/UPIMesh/PeerDiagnosticMessage.swift \
  ios/UPIMesh/UPIMesh/PeerTransportTests.swift \
  ios/UPIMesh/UPIMesh/APIConfiguration.swift \
  ios/UPIMesh/UPIMesh/UPIMeshAPIClient.swift \
  ios/UPIMesh/UPIMesh/OfflineReconciliationService.swift \
  ios/UPIMesh/UPIMesh/ReconciliationServiceTests.swift \
  ios/UPIMesh/UPIMesh/PreviewModels.swift \
  ios/UPIMesh/UPIMesh/MeshLedgerViewModel.swift \
  ios/UPIMesh/UPIMesh/MeshLedgerViewModelTests.swift \
  ios/UPIMesh/run_offline_tests.swift \
  -o /tmp/run_offline_tests

/tmp/run_offline_tests
rm -f /tmp/run_offline_tests

echo ""
echo "=== Building and Running macOS Peer Test Companion Tests (Stage 6.3C) ==="
swiftc -framework Foundation -framework Security -framework CryptoKit \
  ios/UPIMesh/UPIMesh/PaymentInstruction.swift \
  ios/UPIMesh/UPIMesh/OfflinePaymentPacket.swift \
  ios/UPIMesh/UPIMesh/PeerTransferMessage.swift \
  ios/UPIMesh/UPIMesh/PeerDiagnosticMessage.swift \
  macos/UPIMeshCompanion/MacDeviceIdentityManager.swift \
  macos/UPIMeshCompanion/MacReceivedPacketStore.swift \
  macos/UPIMeshCompanion/MacBridgeClient.swift \
  macos/UPIMeshCompanion/MacCompanionTests.swift \
  macos/UPIMeshCompanion/run_mac_tests.swift \
  -o /tmp/run_mac_tests
/tmp/run_mac_tests
rm -f /tmp/run_mac_tests

