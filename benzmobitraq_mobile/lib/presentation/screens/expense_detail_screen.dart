import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../data/models/expense_claim_comment_model.dart';
import '../../data/models/expense_claim_event_model.dart';
import '../../data/models/expense_claim_attachment_model.dart';
import '../../data/repositories/expense_repository.dart';
import '../blocs/auth/auth_bloc.dart';

/// Detail screen for viewing an expense claim with chat, timeline, and attachments
class ExpenseDetailScreen extends StatefulWidget {
  final String claimId;
  final String claimTitle;
  
  const ExpenseDetailScreen({
    Key? key,
    required this.claimId,
    required this.claimTitle,
  }) : super(key: key);

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _commentController = TextEditingController();
  
  List<ExpenseClaimComment> _comments = [];
  List<ExpenseClaimEvent> _events = [];
  List<ExpenseClaimAttachment> _attachments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    final repo = context.read<ExpenseRepository>();
    
    // Load everything in parallel
    final results = await Future.wait([
      repo.getClaimComments(widget.claimId),
      repo.getClaimEvents(widget.claimId),
      repo.getClaimAttachments(widget.claimId),
    ]);

    setState(() {
      _comments = (results[0] as List<Map<String, dynamic>>)
          .map((json) => ExpenseClaimComment.fromJson({
            ...json,
            'author_name': json['author']?['name'],
            'author_role': json['author']?['role'],
          }))
          .toList();
      
      _events = (results[1] as List<Map<String, dynamic>>)
          .map((json) => ExpenseClaimEvent.fromJson({
            ...json,
            'actor_name': json['actor']?['name'],
            'actor_role': json['actor']?['role'],
          }))
          .toList();
      
      _attachments = (results[2] as List<Map<String, dynamic>>)
          .map((json) => ExpenseClaimAttachment.fromJson({
            ...json,
            'uploader_name': json['uploader']?['name'],
          }))
          .toList();
      
      _loading = false;
    });
  }

  Future<void> _sendComment() async {
    if (_commentController.text.trim().isEmpty) return;
    
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final repo = context.read<ExpenseRepository>();
    final result = await repo.addComment(
      claimId: widget.claimId,
      authorId: authState.employee.id,
      body: _commentController.text.trim(),
    );

    if (result != null) {
      _commentController.clear();
      await _loadData(); // Reload to show new comment
    }
  }

  Future<void> _pickAndUploadFile() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image == null) return;

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final repo = context.read<ExpenseRepository>();
    final file = File(image.path);
    
    // Determine MIME type
    final extension = image.path.split('.').last.toLowerCase();
    final mimeType = extension == 'pdf' 
        ? 'application/pdf' 
        : 'image/$extension';

    final result = await repo.uploadAttachment(
      claimId: widget.claimId,
      uploadedBy: authState.employee.id,
      file: file,
      originalFilename: image.name,
      mimeType: mimeType,
    );

    if (result != null) {
      await _loadData(); // Reload to show new attachment
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attachment uploaded successfully')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.claimTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
            Tab(icon: Icon(Icons.timeline), text: 'Timeline'),
            Tab(icon: Icon(Icons.attach_file), text: 'Attachments'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildChatTab(),
                _buildTimelineTab(),
                _buildAttachmentsTab(),
              ],
            ),
    );
  }

  // ============================================================
  // CHAT TAB
  // ============================================================
  
  Widget _buildChatTab() {
    return Column(
      children: [
        Expanded(
          child: _comments.isEmpty
              ? const Center(child: Text('No messages yet'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _comments.length,
                  itemBuilder: (context, index) {
                    final comment = _comments[index];
                    final isMe = comment.authorId == 
                        (context.read<AuthBloc>().state as AuthAuthenticated).employee.id;
                    
                    return _buildChatBubble(comment, isMe);
                  },
                ),
        ),
        _buildChatInput(),
      ],
    );
  }

  Widget _buildChatBubble(ExpenseClaimComment comment, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe ? Colors.blue[100] : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe && comment.authorName != null)
                Text(
                  comment.authorName!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 4),
              Text(comment.body),
              const SizedBox(height: 4),
              Text(
                DateFormat('MMM d, h:mm a').format(comment.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            color: Colors.blue,
            onPressed: _sendComment,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TIMELINE TAB
  // ============================================================
  
  Widget _buildTimelineTab() {
    if (_events.isEmpty) {
      return const Center(child: Text('No activity yet'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      itemBuilder: (context, index) {
        final event = _events[index];
        return _buildTimelineItem(event);
      },
    );
  }

  Widget _buildTimelineItem(ExpenseClaimEvent event) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot and line
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 2,
                height: 40,
                color: Colors.grey[300],
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Event details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.getDescription(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  '${event.actorName ?? 'Unknown'} • ${DateFormat('MMM d, h:mm a').format(event.createdAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (event.note != null) ...[
                  const SizedBox(height: 8),
                  Text(event.note!, style: const TextStyle(fontSize: 14)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ATTACHMENTS TAB
  // ============================================================
  
  Widget _buildAttachmentsTab() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.add_photo_alternate),
          title: const Text('Upload Attachment'),
          onTap: _pickAndUploadFile,
        ),
        const Divider(),
        Expanded(
          child: _attachments.isEmpty
              ? const Center(child: Text('No attachments yet'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _attachments.length,
                  itemBuilder: (context, index) {
                    final attachment = _attachments[index];
                    return _buildAttachmentCard(attachment);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAttachmentCard(ExpenseClaimAttachment attachment) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          attachment.isImage ? Icons.image : Icons.picture_as_pdf,
          size: 40,
          color: attachment.isImage ? Colors.blue : Colors.red,
        ),
        title: Text(attachment.originalFilename),
        subtitle: Text(
          '${attachment.fileSizeFormatted} • ${DateFormat('MMM d, yyyy').format(attachment.uploadedAt)}',
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'view',
              child: Text('View'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete'),
            ),
          ],
          onSelected: (value) async {
            if (value == 'view') {
              // TODO: Open attachment viewer
            } else if (value == 'delete') {
              final repo = context.read<ExpenseRepository>();
              await repo.deleteAttachment(
                attachmentId: attachment.id,
                path: attachment.path,
              );
              await _loadData();
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    super.dispose();
  }
}
