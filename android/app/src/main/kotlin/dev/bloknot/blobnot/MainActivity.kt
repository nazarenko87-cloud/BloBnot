package dev.bloknot.blobnot

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Storage Access Framework bridge (`bloknot/saf`). A "SAF vault" is a
 * persisted tree Uri; note paths inside it are relative, '/'-separated.
 */
class MainActivity : FlutterActivity() {
    private val channel = "bloknot/saf"
    private var pendingResult: MethodChannel.Result? = null
    private val openTreeRequest = 42

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                val tree = call.argument<String>("tree")
                val path = call.argument<String>("path")
                when (call.method) {
                    "pickTree" -> pickTree(result)
                    "hasPermission" -> result.success(hasPermission(tree))
                    "listMarkdown" -> result.success(listMarkdown(tree!!))
                    "listFolder" -> result.success(listFolder(tree!!, path!!))
                    "listDirs" -> result.success(listDirs(tree!!))
                    "readFile" -> result.success(readFile(tree!!, path!!))
                    "writeFile" -> {
                        writeText(tree!!, path!!, call.argument<String>("content")!!)
                        result.success(null)
                    }
                    "writeBytes" -> {
                        writeBytes(tree!!, path!!, call.argument<ByteArray>("bytes")!!)
                        result.success(null)
                    }
                    "delete" -> {
                        findFile(tree!!, path!!)?.delete()
                        result.success(null)
                    }
                    "rename" -> {
                        rename(tree!!, path!!, call.argument<String>("newPath")!!)
                        result.success(null)
                    }
                    "mkdir" -> {
                        ensureDir(tree!!, path!!)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickTree(result: MethodChannel.Result) {
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        startActivityForResult(intent, openTreeRequest)
    }

    override fun onActivityResult(request: Int, code: Int, data: Intent?) {
        super.onActivityResult(request, code, data)
        if (request != openTreeRequest) return
        val res = pendingResult ?: return
        pendingResult = null
        val uri = data?.data
        if (code == Activity.RESULT_OK && uri != null) {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
            res.success(uri.toString())
        } else {
            res.success(null)
        }
    }

    private fun hasPermission(tree: String?): Boolean {
        if (tree == null) return false
        val uri = Uri.parse(tree)
        return contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission && it.isWritePermission
        }
    }

    private fun root(tree: String): DocumentFile? =
        DocumentFile.fromTreeUri(this, Uri.parse(tree))

    /** Reserved folders that are not shown as notes/projects. */
    private val reserved = setOf("_archive", "_templates", "attachments", ".history")

    private fun listMarkdown(tree: String): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val r = root(tree) ?: return out
        fun walk(dir: DocumentFile, prefix: String, depth: Int) {
            for (child in dir.listFiles()) {
                val name = child.name ?: continue
                if (child.isDirectory) {
                    if (name.startsWith(".") || name in reserved) continue
                    walk(child, "$prefix$name/", depth + 1)
                } else if (name.lowercase().endsWith(".md")) {
                    out.add(
                        mapOf(
                            "relPath" to "$prefix$name",
                            "modified" to child.lastModified()
                        )
                    )
                }
            }
        }
        walk(r, "", 0)
        return out
    }

    /** Shallow list of `.md` files in one folder (e.g. `_archive`,
     *  `_templates`) that [listMarkdown] deliberately skips. `relDir` empty =
     *  vault root. */
    private fun listFolder(tree: String, relDir: String): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val dir = if (relDir.isEmpty()) root(tree) else findDir(tree, relDir)
        dir ?: return out
        for (child in dir.listFiles()) {
            val name = child.name ?: continue
            if (!child.isDirectory && name.lowercase().endsWith(".md")) {
                out.add(mapOf("relPath" to name, "modified" to child.lastModified()))
            }
        }
        return out
    }

    /** First-level subfolder names, minus dot- and reserved folders. */
    private fun listDirs(tree: String): List<String> {
        val r = root(tree) ?: return emptyList()
        return r.listFiles()
            .filter { it.isDirectory }
            .mapNotNull { it.name }
            .filter { !it.startsWith(".") && it !in reserved }
    }

    private fun findDir(tree: String, relDir: String): DocumentFile? {
        var cur = root(tree) ?: return null
        for (part in relDir.split("/").filter { it.isNotEmpty() }) {
            cur = cur.findFile(part)?.takeIf { it.isDirectory } ?: return null
        }
        return cur
    }

    private fun findFile(tree: String, relPath: String): DocumentFile? {
        var cur = root(tree) ?: return null
        val parts = relPath.split("/").filter { it.isNotEmpty() }
        for ((i, part) in parts.withIndex()) {
            cur = cur.findFile(part) ?: return null
            if (i < parts.size - 1 && !cur.isDirectory) return null
        }
        return cur
    }

    private fun ensureDir(tree: String, relDir: String): DocumentFile? {
        var cur = root(tree) ?: return null
        for (part in relDir.split("/").filter { it.isNotEmpty() }) {
            cur = cur.findFile(part)?.takeIf { it.isDirectory }
                ?: cur.createDirectory(part) ?: return null
        }
        return cur
    }

    private fun createFile(tree: String, relPath: String): DocumentFile? {
        val parts = relPath.split("/").filter { it.isNotEmpty() }
        val parent = if (parts.size > 1) {
            ensureDir(tree, parts.dropLast(1).joinToString("/"))
        } else {
            root(tree)
        } ?: return null
        val name = parts.last()
        parent.findFile(name)?.let { return it }
        return parent.createFile("text/markdown", name)
    }

    private fun readFile(tree: String, relPath: String): String {
        val f = findFile(tree, relPath) ?: return ""
        return contentResolver.openInputStream(f.uri)?.use {
            it.readBytes().toString(Charsets.UTF_8)
        } ?: ""
    }

    private fun writeText(tree: String, relPath: String, content: String) =
        writeBytes(tree, relPath, content.toByteArray(Charsets.UTF_8))

    private fun writeBytes(tree: String, relPath: String, bytes: ByteArray) {
        val f = findFile(tree, relPath) ?: createFile(tree, relPath) ?: return
        // "wt" truncates before writing.
        contentResolver.openOutputStream(f.uri, "wt")?.use { it.write(bytes) }
    }

    private fun rename(tree: String, relPath: String, newRelPath: String) {
        val f = findFile(tree, relPath) ?: return
        val newName = newRelPath.split("/").last()
        f.renameTo(newName)
    }
}
