#include "alpm-util.h"

alpm_pkg_t* alpm_pkg_load_file (alpm_handle_t *handle, const char *filename, int full, alpm_siglevel_t level) {
	alpm_pkg_t *p;
	int err = alpm_pkg_load(handle, filename, full, level, &p);
	if (err == -1) return NULL;
	else return p;
}

alpm_list_t* alpm_pkg_get_files_list (alpm_pkg_t* pkg) {
	alpm_list_t *list = NULL;
	alpm_filelist_t *pkgfiles;
	size_t i;

	pkgfiles = alpm_pkg_get_files(pkg);

	for(i = 0; i < pkgfiles->count; i++) {
		const alpm_file_t *file = pkgfiles->files + i;
		list = alpm_list_add(list, file);
	}
	return list;
}

void* alpm_list_get_data (alpm_list_t *list) {
	return list->data;
}

void* alpm_list_nth_data (alpm_list_t *list, size_t n) {
	return alpm_list_nth (list, n)->data;
}

alpm_list_t* alpm_list_remove_data (alpm_list_t *list, const void *needle, alpm_list_fn_cmp fn) {
	void *data = NULL;
	list = alpm_list_remove (list, needle, fn, data);
	free(data);
	return list;
}

alpm_list_t* alpm_list_sort_data (alpm_list_t *list, alpm_list_fn_cmp fn) {
	list = alpm_list_msort (list, alpm_list_count (list), fn);
	return list;
}

alpm_list_t *alpm_list_new () {
	return NULL;
}

void alpm_list_free_all (alpm_list_t *list) {
   do { alpm_list_free_inner (list, free); alpm_list_free (list); list = NULL; } while (0);
}

void alpm_list_iterator (alpm_list_t *list, alpm_list_iterator_t* iter) {
	iter->pos = list;
}

void* alpm_list_iterator_next_value (alpm_list_iterator_t *iter) {
	if (iter->pos) {
		void* result = alpm_list_get_data (iter->pos);
		iter->pos = alpm_list_next (iter->pos);
		return result;
	}
	else return NULL;
}
