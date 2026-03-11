const fs = require('fs');
const file = 'c:/Users/user/benzdesk/components/requests/RequestList.tsx';
let lines = fs.readFileSync(file, 'utf8').split('\n');

const startIndex = lines.findIndex(l => l.includes('<div className="space-y-3">'));
const replacement = `                <div className="space-y-3">
                    {filteredRequests.map((request) => (
                        <Link
                            key={request.id}
                            href={\`\${linkPrefix}?id=\${request.id}\`}
                            className="block group"
                        >
                            <Card hover padding="sm" className="bg-white/60 backdrop-blur-md border border-gray-100 shadow-sm transition-all duration-300 hover:-translate-y-1 hover:shadow-lg hover:bg-white/90 group-hover:border-blue-200">
                                <div className="flex items-start justify-between gap-4">
                                    {/* Main content */}
                                    <div className="flex-1 min-w-0">
                                        <div className="flex items-center gap-3 mb-2">
                                            <h3 className="text-base font-semibold text-gray-900 truncate group-hover:text-blue-600 transition-colors">
                                                {request.title}
                                            </h3>
                                            <StatusBadge status={request.status} />
                                        </div>

                                        <p className="text-sm text-gray-500 line-clamp-2 mb-3">
                                            {request.description}
                                        </p>

                                        <div className="flex flex-wrap items-center gap-3 text-xs text-gray-500">
                                            <PriorityBadge priority={request.priority as Priority} size="sm" />

                                            <span className="flex items-center gap-1">
                                                <span className="px-2 py-0.5 rounded bg-gray-100 text-gray-600 font-medium">
                                                    {REQUEST_CATEGORY_LABELS[request.category as keyof typeof REQUEST_CATEGORY_LABELS] || request.category}
                                                </span>
                                            </span>

                                            <span className="flex items-center gap-1" suppressHydrationWarning>
                                                <Clock className="w-3.5 h-3.5" />
                                                {formatDistanceToNow(new Date(request.created_at), { addSuffix: true })}
                                            </span>

                                            {/* Show requester name for admin/director */}
                                            {(isAdmin || isDirector) && request.creator_email && (
                                                <span className="flex items-center gap-1 text-gray-400">
                                                    <User className="w-3.5 h-3.5" />
                                                    {getDisplayName(request.creator_email)}
                                                </span>
                                            )}

                                            {showAssignee && request.assigned_to && (
                                                <span className="flex items-center gap-1 text-blue-500 font-medium">
                                                    <User className="w-3.5 h-3.5" />
                                                    Assigned
                                                </span>
                                            )}
                                        </div>
                                    </div>

                                    {/* Delete button (admin/director only) */}
                                    {(isAdmin || isDirector) && request.status === 'closed' && (
                                        <button
                                            onClick={(e) => {
                                                e.preventDefault();
                                                e.stopPropagation();
                                                if (confirm('Are you sure you want to delete this closed request? This action cannot be undone.')) {
                                                    const supabase = getSupabaseClient();
                                                    supabase
                                                        .from('requests')
                                                        .delete()
                                                        .eq('id', request.id)
                                                        .then(({ error }) => {
                                                            if (error) {
                                                                console.error('Delete failed:', error);
                                                                alert('Failed to delete request');
                                                            } else {
                                                                setRequests(prev => prev.filter(r => r.id !== request.id));
                                                            }
                                                        });
                                                }
                                            }}
                                            className="flex-shrink-0 p-2 text-red-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors"
                                            title="Delete closed request"
                                        >
                                            <Trash2 className="w-4 h-4" />
                                        </button>
                                    )}

                                    {/* Arrow indicator */}
                                    <div className="flex-shrink-0 text-gray-400 group-hover:text-blue-500 transition-colors mt-1">
                                        <ChevronRight className="w-5 h-5" />
                                    </div>
                                </div>
                            </Card>
                        </Link>
                    ))}
                </div>
            )}

            {/* Load more (if limit applied) */}
            {limit && requests.length >= limit && (
                <div className="text-center pt-4">
                    <Button variant="ghost" size="sm">
                        View All Requests
                    </Button>
                </div>
            )}
        </div>
    );
}

export default RequestList;`;

lines.splice(startIndex);
fs.writeFileSync(file, lines.join('\n') + '\n' + replacement);
console.log("Done!");
