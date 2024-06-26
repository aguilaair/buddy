import 'dart:convert';

import 'package:buddy/data/comments.dart';
import 'package:buddy/data/profile.dart';
import 'package:buddy/states/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:buddy/data/post.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class PostState {
  final List<Post> posts;
  final bool loading;
  final String error;

  PostState({
    required this.posts,
    required this.loading,
    required this.error,
  });

  factory PostState.initial() {
    return PostState(
      posts: [],
      loading: false,
      error: '',
    );
  }

  PostState copyWith({
    List<Post>? posts,
    bool? loading,
    String? error,
  }) {
    return PostState(
      posts: posts ?? this.posts,
      loading: loading ?? this.loading,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'posts': posts.map((x) => x.toMap()).toList(),
      'loading': loading,
      'error': error,
    };
  }

  factory PostState.fromMap(Map<String, dynamic> map) {
    return PostState(
      posts: List<Post>.from(map['posts']?.map((x) => Post.fromMap(x))),
      loading: map['loading'] ?? false,
      error: map['error'] ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory PostState.fromJson(String source) =>
      PostState.fromMap(json.decode(source));

  @override
  String toString() =>
      'PostState(posts: $posts, loading: $loading, error: $error)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PostState &&
        listEquals(other.posts, posts) &&
        other.loading == loading &&
        other.error == error;
  }

  @override
  int get hashCode => posts.hashCode ^ loading.hashCode ^ error.hashCode;
}

class PostProvider extends StateNotifier<PostState> {
  final Ref ref;
  final SupabaseClient client = Supabase.instance.client;

  PostProvider(this.ref) : super(PostState.initial()) {
    fetchPosts();
  }

  Future<String> postText(String text) async {
    // Trim, check if empty
    if (text.trim().isEmpty) {
      throw "Post cannot be empty";
    }

    final post = Post(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      createdBy: ref.read(userProvider).profile!.id,
      caption: text.trim(),
    );

    await client.from("posts").insert(post.toPostMap());

    return post.id;
  }

  Future<String> postImage(CroppedFile image, String caption) async {
    // Upload image
    final bytes = await image.readAsBytes();
    final filename =
        "${ref.read(userProvider).profile!.id}/${const Uuid().v4()}.jpg";

    final post = Post(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      createdBy: ref.read(userProvider).profile!.id,
      caption: caption,
      postImageUrl: filename,
    );

    await client.from("posts").insert(post.toPostMap());

    await client.storage.from("posts").uploadBinary(
          filename,
          bytes,
        );

    return post.id;
  }

  Future<List<Post>> fetchPosts(
      {int start = 0, int limit = 20, getAllData = true}) async {
    final posts =
        await client.from("posts").select("*").range(start, limit + start);

    if (getAllData) {
      for (var post in posts) {
        final comments = await fetchComments(post["id"] as String);

        post["comments"] = comments?.map((e) => e.toMapWithProfile()).toList();

        // Also get the user who created the post
        final user = await client
            .from("profile")
            .select("username, personName, profilePic")
            .eq("id", post["createdBy"])
            .single();

        post["username"] = user["username"];
        post["userImageUrl"] = client.storage.from("profile-pics").getPublicUrl(
              user["profilePic"],
            );
        post["petowner"] = user["personName"];
      }
    }

    final newPosts = [
      ...posts.map((e) => Post.fromMap(e)),
    ];

    //Sort by date (newest first)
    newPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    state = state.copyWith(
      posts: newPosts,
    );

    return newPosts;
  }

  Future<List<Comment>>? fetchComments(String postId) async {
    final comments =
        await client.from("comments").select("*").eq("post", postId).limit(100);

    // Get the user who created the comment
    final List<Profile> users = [];
    for (var comment in comments) {
      final userIdx =
          users.indexWhere((element) => element.id == comment["createdBy"]);
      if (userIdx != -1) {
        final user =
            users.firstWhere((element) => element.id == comment["createdBy"]);
        comment["profile"] = user.toMap();
      } else {
        final user = await client
            .from("profile")
            .select("*")
            .eq("id", comment["createdBy"])
            .single();
        users.add(Profile.fromMap(user));
        comment["profile"] = user;
      }
    }

    return comments.map((e) => Comment.fromMap(e)).toList();
  }

  Future<String> postComment(String postId, String content) async {
    // Trim, check if empty
    if (content.trim().isEmpty) {
      throw "Comment cannot be empty";
    }

    final comment = Comment(
      id: const Uuid().v4(),
      post: postId,
      createdAt: DateTime.now(),
      createdBy: ref.read(userProvider).profile!.id,
      content: content.trim(),
    );

    await client.from("comments").insert(comment.toMap());

    return comment.id;
  }

  Future<List<Post>> fetchAccPics(
      {int start = 0, int limit = 20, getAllData = true, String? id}) async {
    id ??= ref.read(userProvider).profile!.id;

    final posts = await client
        .from("posts")
        .select("*")
        .eq("createdBy", id)
        .range(start, limit + start);

    // remove non-image posts
    posts.removeWhere((element) => element["postImageUrl"] == null);

    if (getAllData) {
      final user = await client
          .from("profile")
          .select("username, personName, profilePic")
          .eq("id", id)
          .single();

      for (var post in posts) {
        final comments = await fetchComments(post["id"] as String);

        post["comments"] = comments?.map((e) => e.toMapWithProfile()).toList();

        post["username"] = user["username"];
        post["userImageUrl"] = client.storage.from("profile-pics").getPublicUrl(
              user["profilePic"],
            );
        post["petowner"] = user["personName"];
      }
    }

    final newPosts = [
      ...posts.map((e) => Post.fromMap(e)),
    ];

    // Remove duplicates
    final seen = <String>{};
    newPosts.removeWhere((element) => !seen.add(element.id));

    //Sort by date (newest first)
    newPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return newPosts;
  }

  Future<List<Post>> fetchAccTextPosts({
    int start = 0,
    int limit = 20,
    getAllData = true,
    String? id,
  }) async {
    id ??= ref.read(userProvider).profile!.id;

    final posts = await client
        .from("posts")
        .select("*")
        .eq("createdBy", id)
        .range(start, limit + start);

    // remove non-text-only posts
    posts.removeWhere((element) => element["postImageUrl"] != null);

    if (getAllData) {
      final user = await client
          .from("profile")
          .select("username, personName, profilePic")
          .eq("id", id)
          .single();

      for (var post in posts) {
        final comments = await fetchComments(post["id"] as String);

        post["comments"] = comments?.map((e) => e.toMapWithProfile()).toList();

        post["username"] = user["username"];
        post["userImageUrl"] = client.storage.from("profile-pics").getPublicUrl(
              user["profilePic"],
            );
        post["petowner"] = user["personName"];
      }
    }

    final newPosts = [
      ...posts.map((e) => Post.fromMap(e)),
    ];

    // Remove duplicates
    final seen = <String>{};
    newPosts.removeWhere((element) => !seen.add(element.id));

    //Sort by date (newest first)
    newPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return newPosts;
  }

  Future<Post> fetchPost(String id) async {
    final post = await client.from("posts").select("*").eq("id", id).single();

    final comments = await fetchComments(id);

    post["comments"] = comments?.map((e) => e.toMapWithProfile()).toList();

    final user = await client
        .from("profile")
        .select("username, personName, profilePic")
        .eq("id", post["createdBy"])
        .single();

    post["username"] = user["username"];
    post["userImageUrl"] = client.storage.from("profile-pics").getPublicUrl(
          user["profilePic"],
        );
    post["petowner"] = user["personName"];

    return Post.fromMap(post);
  }
}
