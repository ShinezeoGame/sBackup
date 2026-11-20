package com.shinezeogame.sbackup

import android.content.Context
import android.provider.MediaStore

/**
 * Lecture de la galerie d'Android (MediaStore) : albums, et photos et vidéos d'albums
 * choisis. Les fichiers sont ensuite lus par leur chemin, ce qu'Android autorise avec
 * l'accès aux photos et vidéos ; avec ACCESS_MEDIA_LOCATION, la position GPS des photos
 * n'est pas effacée à la lecture.
 */
object MediaQueries {
    private val uri = MediaStore.Files.getContentUri("external")

    // Seulement les photos et les vidéos terminées (pas un enregistrement en cours).
    private const val SELECTION =
        "(${MediaStore.Files.FileColumns.MEDIA_TYPE} = ${MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE} OR " +
            "${MediaStore.Files.FileColumns.MEDIA_TYPE} = ${MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO}) AND " +
            "${MediaStore.MediaColumns.IS_PENDING} = 0"

    fun albums(context: Context): List<Map<String, Any?>> {
        val projection = arrayOf(
            MediaStore.MediaColumns.BUCKET_ID,
            MediaStore.MediaColumns.BUCKET_DISPLAY_NAME,
            MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.MediaColumns.SIZE,
        )
        val albums = LinkedHashMap<String, MutableMap<String, Any?>>()
        context.contentResolver.query(uri, projection, SELECTION, null, null)?.use { c ->
            while (c.moveToNext()) {
                val id = c.getString(0) ?: continue
                val album = albums.getOrPut(id) {
                    mutableMapOf(
                        "id" to id,
                        "nom" to (c.getString(1) ?: "Sans nom"),
                        "chemin" to (c.getString(2) ?: ""),
                        "nombre" to 0,
                        "octets" to 0L,
                    )
                }
                album["nombre"] = (album["nombre"] as Int) + 1
                album["octets"] = (album["octets"] as Long) + c.getLong(3)
            }
        }
        return albums.values.sortedByDescending { it["nombre"] as Int }
    }

    @Suppress("DEPRECATION") // DATA : chemin du fichier, toujours fourni et lisible
    fun media(context: Context, albumIds: List<String>): List<Map<String, Any?>> {
        if (albumIds.isEmpty()) return emptyList()
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.BUCKET_ID,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
        )
        val placeholders = albumIds.joinToString(",") { "?" }
        val selection = "$SELECTION AND ${MediaStore.MediaColumns.BUCKET_ID} IN ($placeholders)"
        val items = ArrayList<Map<String, Any?>>()
        context.contentResolver.query(uri, projection, selection, albumIds.toTypedArray(), null)?.use { c ->
            while (c.moveToNext()) {
                val path = c.getString(2) ?: continue
                val size = c.getLong(3)
                if (size <= 0) continue
                val added = c.getLong(5) * 1000
                val taken = if (c.isNull(4) || c.getLong(4) <= 0) added else c.getLong(4)
                items.add(
                    mapOf(
                        "id" to c.getLong(0),
                        "nom" to (c.getString(1) ?: path.substringAfterLast('/')),
                        "chemin" to path,
                        "taille" to size,
                        "prise" to taken,
                        "modifie" to c.getLong(6) * 1000,
                        "album" to (c.getString(7) ?: ""),
                        "video" to (c.getInt(8) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO),
                    ),
                )
            }
        }
        return items
    }
}
