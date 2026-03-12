import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/di/injection.dart';
import '../../data/repositories/expense_repository.dart';
import '../../core/utils/image_picker_helper.dart';

import 'package:path/path.dart' as p;
import '../blocs/auth/auth_bloc.dart';

/// Expense Detail Screen with chat/messages — unified with BenzDesk
/// Uses request_comments (same as BenzDesk web) for trip expenses,
/// and expense_claim_comments for standalone claims.
class ExpenseDetailScreen extends StatefulWidget {
  final String claimId;
  final String? category;
  final double? amount;
  final String? status;

  const ExpenseDetailScreen({
    super.key,
    required this.claimId,
    this.category,
    this.amount,
    this.status,
  });

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _comments = [];
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _attachments = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isUploading = false;
  bool _isTripExpense = false; // True if this is in the requests table (trip expense)
  String? _currentStatus; // Mutable status string 

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.status;
    _loadData();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;

    try {
      // 1. Check if this expense exists in the requests table (trip expense flow)
      final reqCheck = await supabase
          .from('requests')
          .select('id')
          .eq('reference_id', widget.claimId)
          .maybeSingle();

      _isTripExpense = reqCheck != null;

      if (_isTripExpense) {
        // Use BenzDesk request_comments/request_events/request_attachments
        final requestId = reqCheck!['id'];
        
        // Fetch up-to-date status
        final reqDetails = await supabase.from('requests').select('status').eq('id', requestId).single();

        final results = await Future.wait([
          supabase
              .from('request_comments')
              .select('*, author:employees(name)')
              .eq('request_id', requestId)
              .order('created_at', ascending: true),
          supabase
              .from('request_events')
              .select('*')
              .eq('request_id', requestId)
              .order('created_at', ascending: true),
          supabase
              .from('request_attachments')
              .select('*')
              .eq('request_id', requestId)
              .order('uploaded_at', ascending: true),
        ]);

        if (mounted) {
          setState(() {
            _currentStatus = reqDetails['status'];
            _comments = List<Map<String, dynamic>>.from(results[0] as List);
            _events = List<Map<String, dynamic>>.from(results[1] as List);
            _attachments = List<Map<String, dynamic>>.from(results[2] as List);
            _isLoading = false;
          });
        }
      } else {
        // Fetch up-to-date status
        final claimDetails = await supabase.from('expense_claims').select('status').eq('id', widget.claimId).single();
        
        // Use expense_claim_comments for standalone claims
        final repo = getIt<ExpenseRepository>();
        final results = await Future.wait([
          repo.getClaimComments(widget.claimId),
          repo.getClaimEvents(widget.claimId),
          repo.getClaimAttachments(widget.claimId),
        ]);

        if (mounted) {
          setState(() {
            _currentStatus = claimDetails['status'];
            _comments = results[0];
            _events = results[1];
            _attachments = results[2];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading detail data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final authState = context.read<AuthBloc>().state;
    final employeeId = authState is AuthAuthenticated ? authState.employee.id : null;
    if (employeeId == null) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final supabase = Supabase.instance.client;

      if (_isTripExpense) {
        // Insert into request_comments (same as BenzDesk web)
        final reqCheck = await supabase.from('requests').select('id').eq('reference_id', widget.claimId).single();
        final response = await supabase
            .from('request_comments')
            .insert({
              'request_id': reqCheck['id'],
              'author_id': employeeId,
              'body': text,
              'is_internal': false,
            })
            .select()
            .single();

        if (mounted) {
          await _loadData();
          setState(() {
            _isSending = false;
          });
          _scrollToBottom();
        }
      } else {
        // Insert into expense_claim_comments for standalone claims
        final repo = getIt<ExpenseRepository>();
        final result = await repo.addComment(
          claimId: widget.claimId,
          authorId: employeeId,
          body: text,
        );

        if (result != null && mounted) {
          await _loadData();
          setState(() {
            _isSending = false;
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickAndUploadAttachment() async {
    final authState = context.read<AuthBloc>().state;
    final employeeId = authState is AuthAuthenticated ? authState.employee.id : null;
    if (employeeId == null) return;

    final file = await ImagePickerHelper.pickFile();
    if (file == null) return;

    setState(() => _isUploading = true);

    try {
      final supabase = Supabase.instance.client;
      final fileExtension = p.extension(file.path).toLowerCase();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}$fileExtension';
      final storagePath = '$_isTripExpense ? requests : expense_claims/${widget.claimId}/$fileName';

      // Upload to storage 
      final storageBucket = supabase.storage.from('request_attachments');
      await storageBucket.upload(
        storagePath,
        file,
        fileOptions: FileOptions(
          contentType: _getContentType(fileExtension),
        ),
      );

      final publicUrl = storageBucket.getPublicUrl(storagePath);

      // Save attachment record
      if (_isTripExpense) {
        final reqCheck = await supabase.from('requests').select('id').eq('reference_id', widget.claimId).single();
        final response = await supabase
            .from('request_attachments')
            .insert({
              'request_id': reqCheck['id'],
              'uploaded_by': employeeId,
              'file_name': p.basename(file.path),
              'file_url': publicUrl,
              'mime_type': _getContentType(fileExtension),
              'size_bytes': await file.length(),
            })
            .select()
            .single();

        if (mounted) {
          setState(() {
            _attachments.add(response);
            _isUploading = false;
          });
        }
      } else {
        final repo = getIt<ExpenseRepository>();
        // Wait for repository upload implementation or just reload data
        await _loadData(); 
        if (mounted) {
           setState(() => _isUploading = false);
        }
      }

    } catch (e) {
      debugPrint('Error uploading attachment: $e');
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload attachment: $e')),
        );
      }
    }
  }

  String _getContentType(String extension) {
    switch (extension) {
      case '.pdf': return 'application/pdf';
      case '.png': return 'image/png';
      case '.jpg':
      case '.jpeg': return 'image/jpeg';
      default: return 'application/octet-stream';
    }
  }

  Future<void> _confirmClosure() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final newStatus = 'closed';

      if (_isTripExpense) {
        await supabase
            .from('requests')
            .update({'status': newStatus})
            .eq('id', widget.claimId);
            
         await supabase.from('request_events').insert({
            'request_id': widget.claimId,
            'actor_id': (context.read<AuthBloc>().state as AuthAuthenticated).employee.id,
            'event_type': 'status_change',
            'old_status': 'pending_closure',
            'new_status': newStatus,
          });
      } else {
        await supabase
            .from('expense_claims')
            .update({'status': newStatus})
            .eq('id', widget.claimId);
            
         await supabase.from('expense_claim_events').insert({
            'claim_id': widget.claimId,
            'actor_id': (context.read<AuthBloc>().state as AuthAuthenticated).employee.id,
            'event_type': 'status_change',
            'old_status': 'pending_closure',
            'new_status': newStatus,
          });
      }

      if (mounted) {
        setState(() {
          _currentStatus = newStatus;
        });
        await _loadData();
      }
    } catch (e) {
      debugPrint('Error closing request: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to close request')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
      case 'closed':
      case 'resolved':
        return const Color(0xFF10B981); // Emerald Green
      case 'rejected':
        return const Color(0xFFEF4444); // Red
      case 'in_review':
      case 'in_progress':
        return const Color(0xFF3B82F6); // Blue
      case 'pending_closure':
        return const Color(0xFF8B5CF6); // Purple
      default:
        return const Color(0xFFF59E0B); // Amber
    }
  }

  String _getStatusLabel(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return 'APPROVED';
      case 'closed':
      case 'resolved':
        return 'CLOSED';
      case 'rejected':
        return 'REJECTED';
      case 'in_review':
      case 'in_progress':
        return 'IN REVIEW';
      case 'pending_closure':
        return 'CONFIRM CLOSURE';
      default:
        return 'PENDING';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(_currentStatus);
    final statusLabel = _getStatusLabel(_currentStatus);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Expense Details'),
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header Card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border(
                      left: BorderSide(color: statusColor, width: 4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              widget.category?.toUpperCase().replaceAll('_', ' ') ?? 'EXPENSE',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '₹${widget.amount?.toStringAsFixed(0) ?? '0'}',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      if (_isTripExpense)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.phone_android, size: 14, color: Colors.blue.shade400),
                              const SizedBox(width: 4),
                              Text(
                                'From BenzMobiTraq Trip',
                                style: TextStyle(fontSize: 12, color: Colors.blue.shade400, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Attachments Section
                if (_attachments.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.attach_file, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          'Attachments (${_attachments.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _attachments.length,
                      itemBuilder: (context, index) {
                        final att = _attachments[index];
                        final filename = att['original_filename'] ?? att['file_name'] ?? 'File';
                        final mimeType = att['mime_type'] ?? att['content_type'] ?? '';
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getFileIcon(mimeType.toString()),
                                size: 24,
                                color: Colors.blue.shade400,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    filename.toString(),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _formatFileSize((att['size_bytes'] ?? att['file_size'] ?? 0) as int),
                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Activity / Chat Section Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Activity & Messages',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Closure Banner
                if (_currentStatus?.toLowerCase() == 'pending_closure')
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF), // Purple 100
                      border: Border.all(color: const Color(0xFFD8B4FE)), // Purple 300
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, color: Color(0xFF7E22CE), size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Action Required',
                              style: TextStyle(
                                color: Color(0xFF7E22CE), // Purple 700
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your admin has marked this request as ready to close. Please confirm if the issue is resolved or the reimbursement is settled.',
                          style: TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _confirmClosure,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF9333EA), // Purple 600
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Confirm & Close Request'),
                        ),
                      ],
                    ),
                  ),

                // Chat Messages
                Expanded(child: _buildChatSection()),

                // Message Input Bar
                _buildMessageInput(),
              ],
            ),
    );
  }

  Widget _buildChatSection() {
    final timeline = <_TimelineItem>[];

    for (final comment in _comments) {
      // request_comments uses author_id and body
      // expense_claim_comments uses author_id and body (via joined author relation)
      final authorName = comment['author']?['name'] ?? comment['author_name'] ?? comment['author_id'] ?? 'Unknown';
      timeline.add(_TimelineItem(
        type: _TimelineType.comment,
        timestamp: DateTime.tryParse(comment['created_at'] ?? '') ?? DateTime.now(),
        authorName: authorName.toString(),
        authorId: (comment['author_id'] ?? '').toString(),
        body: (comment['body'] ?? '').toString(),
        isInternal: comment['is_internal'] == true,
      ));
    }

    for (final event in _events) {
      final actorName = event['actor']?['name'] ?? event['actor_name'] ?? event['actor_id'] ?? 'System';
      timeline.add(_TimelineItem(
        type: _TimelineType.event,
        timestamp: DateTime.tryParse(event['created_at'] ?? '') ?? DateTime.now(),
        authorName: actorName.toString(),
        authorId: '',
        body: (event['event_type'] ?? event['type'] ?? '').toString(),
      ));
    }

    timeline.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (timeline.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'No messages yet',
              style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              'Start the conversation below',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: timeline.length,
      itemBuilder: (context, index) {
        final item = timeline[index];
        if (item.type == _TimelineType.event) {
          return _buildEventBubble(item);
        }
        return _buildCommentBubble(item);
      },
    );
  }

  Widget _buildEventBubble(_TimelineItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '${item.authorName} • ${item.body.replaceAll('_', ' ')}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommentBubble(_TimelineItem item) {
    final authState = context.read<AuthBloc>().state;
    final currentId = authState is AuthAuthenticated ? authState.employee.id : '';
    final isMe = item.authorId == currentId;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF3B82F6) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  item.authorName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isMe ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
              ),
            Text(
              item.body,
              style: TextStyle(
                fontSize: 14,
                color: isMe ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('hh:mm a, dd MMM').format(item.timestamp.toLocal()),
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white54 : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _isUploading ? null : _pickAndUploadAttachment,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  shape: BoxShape.circle,
                ),
                child: _isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.attach_file, color: Colors.grey.shade600, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: const Color(0xFF3B82F6),
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: _isSending ? null : _sendMessage,
              child: Container(
                padding: const EdgeInsets.all(10),
                child: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String mimeType) {
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('image')) return Icons.image;
    if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) return Icons.table_chart;
    return Icons.insert_drive_file;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
}

enum _TimelineType { comment, event }

class _TimelineItem {
  final _TimelineType type;
  final DateTime timestamp;
  final String authorName;
  final String authorId;
  final String body;
  final bool isInternal;

  _TimelineItem({
    required this.type,
    required this.timestamp,
    required this.authorName,
    required this.authorId,
    required this.body,
    this.isInternal = false,
  });
}
