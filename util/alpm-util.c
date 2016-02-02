#include "alpm-util.h"

alpm_pkg_t* alpm_pkg_load_file (alpm_handle_t* handle, const char* filename, int full, alpm_siglevel_t level) {
	alpm_pkg_t* p;
	if (alpm_pkg_load(handle, filename, full, level, &p) != -1) {
		return p;
	} else {
		return NULL;
	}
}

alpm_list_t* alpm_pkg_get_files_list (alpm_pkg_t* pkg) {
	alpm_list_t* list = NULL;
	alpm_filelist_t* pkgfiles;
	size_t i;

	pkgfiles = alpm_pkg_get_files(pkg);

	for(i = 0; i < pkgfiles->count; i++) {
		const alpm_file_t* file = pkgfiles->files + i;
		list = alpm_list_add(list, file);
	}
	return list;
}

void* alpm_list_get_data (alpm_list_t* list) {
	if (list) {
		return list->data;
	} else {
		return NULL;
	}
}

alpm_list_t* alpm_list_sort (alpm_list_t* list, alpm_list_fn_cmp fn) {
	list = alpm_list_msort (list, alpm_list_count (list), fn);
	return list;
}

alpm_list_t* alpm_list_new () {
	return NULL;
}

void alpm_list_free_data (alpm_list_t* list) {
	alpm_list_free_inner (list, free);
}

void alpm_list_iterator (alpm_list_t* list, alpm_list_iterator_t* iter) {
	iter->pos = list;
}

void* alpm_list_iterator_next_value (alpm_list_iterator_t* iter) {
	if (iter->pos) {
		void* data = alpm_list_get_data (iter->pos);
		iter->pos = alpm_list_next (iter->pos);
		return data;
	} else {
		return NULL;
	}
}
