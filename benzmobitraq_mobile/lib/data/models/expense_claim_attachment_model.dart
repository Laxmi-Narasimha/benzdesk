import 'dart:io';
import 'package:equatable/equatable.dart';

/// File attachment on an expense claim (receipt/bill)
class ExpenseClaimAttachment extends Equatable {
  final int id;
  final String claimId;
  final String uploadedBy;
  final String bucket;
  final String path;
  final String originalFilename;
  final String mimeType;
  final int sizeBytes;
  final DateTime uploadedAt;
  
  // Optional fields
  final String? uploaderName;
  final String? publicUrl; // Signed URL for download

  const ExpenseClaimAttachment({
    required this.id,
    required this.claimId,
    required this.uploadedBy,
    this.bucket = 'benzmobitraq-receipts',
    required this.path,
    required this.originalFilename,
    required this.mimeType,
    required this.sizeBytes,
    required this.uploadedAt,
    this.uploaderName,
    this.publicUrl,
  });

  factory ExpenseClaimAttachment.fromJson(Map<String, dynamic> json) {
    return ExpenseClaimAttachment(
      id: json['id'] as int,
      claimId: json['claim_id'] as String,
      uploadedBy: json['uploaded_by'] as String,
      bucket: json['bucket'] as String? ?? 'benzmobitraq-receipts',
      path: json['path'] as String,
      originalFilename: json['original_filename'] as String,
      mimeType: json['mime_type'] as String,
      sizeBytes: json['size_bytes'] as int,
      uploadedAt: DateTime.parse(json['uploaded_at'] as String),
      uploaderName: json['uploader_name'] as String?,
      publicUrl: json['public_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'claim_id': claimId,
    'uploaded_by': uploadedBy,
    'bucket': bucket,
    'path': path,
    'original_filename': originalFilename,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'uploaded_at': uploadedAt.toIso8601String(),
  };
  
  /// Create for insertion (without ID)
  Map<String, dynamic> toInsertJson() => {
    'claim_id': claimId,
    'uploaded_by': uploadedBy,
    'bucket': bucket,
    'path': path,
    'original_filename': originalFilename,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
  };

  /// Check if this is an image
  bool get isImage => mimeType.startsWith('image/');

  /// Check if this is a PDF
  bool get isPdf => mimeType == 'application/pdf';

  /// Get file extension
  String get extension {
    final parts = originalFilename.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  /// Get human-readable file size
  String get fileSizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  List<Object?> get props => [
    id,
    claimId,
    uploadedBy,
    bucket,
    path,
    originalFilename,
    mimeType,
    sizeBytes,
    uploadedAt,
    uploaderName,
    publicUrl,
  ];
}
