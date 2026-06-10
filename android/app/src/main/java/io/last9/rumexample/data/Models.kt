package io.last9.rumexample.data

import org.json.JSONArray
import org.json.JSONObject

data class Post(val id: Int, val userId: Int, val title: String, val body: String)
data class Comment(val id: Int, val postId: Int, val name: String, val email: String, val body: String)
data class User(val id: Int, val name: String, val email: String)
data class Todo(val id: Int, val userId: Int, val title: String, val completed: Boolean)

fun parsePosts(json: String): List<Post> = mapArray(json) {
    Post(it.optInt("id"), it.optInt("userId"), it.optString("title"), it.optString("body"))
}

fun parsePost(json: String): Post? = runCatching {
    val o = JSONObject(json)
    Post(o.optInt("id"), o.optInt("userId"), o.optString("title"), o.optString("body"))
}.getOrNull()

fun parseComments(json: String): List<Comment> = mapArray(json) {
    Comment(it.optInt("id"), it.optInt("postId"), it.optString("name"), it.optString("email"), it.optString("body"))
}

fun parseUsers(json: String): List<User> = mapArray(json) {
    User(it.optInt("id"), it.optString("name"), it.optString("email"))
}

fun parseTodos(json: String): List<Todo> = mapArray(json) {
    Todo(it.optInt("id"), it.optInt("userId"), it.optString("title"), it.optBoolean("completed"))
}

fun parseTodo(json: String): Todo? = runCatching {
    val o = JSONObject(json)
    Todo(o.optInt("id"), o.optInt("userId"), o.optString("title"), o.optBoolean("completed"))
}.getOrNull()

private inline fun <T> mapArray(json: String, crossinline f: (JSONObject) -> T): List<T> = runCatching {
    val arr = JSONArray(json)
    (0 until arr.length()).map { f(arr.getJSONObject(it)) }
}.getOrDefault(emptyList())
