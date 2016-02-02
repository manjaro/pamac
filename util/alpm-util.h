#ifndef ALPM_UTIL_H
#define ALPM_UTIL_H

#include <alpm.h>

typedef struct __alpm_list_iterator_t {
    alpm_list_t* pos;
} alpm_list_iterator_t;

void* alpm_list_get_data (alpm_list_t* list);
alpm_list_t* alpm_list_sort (alpm_list_t* list, alpm_list_fn_cmp fn);
alpm_list_t* alpm_list_new ();
void alpm_list_free_data (alpm_list_t* list);
void alpm_list_iterator (alpm_list_t* list, alpm_list_iterator_t* i);
void* alpm_list_iterator_next_value (alpm_list_iterator_t* iter);

alpm_pkg_t* alpm_pkg_load_file (alpm_handle_t* handle, const char* filename, int full, alpm_siglevel_t level);
alpm_list_t* alpm_pkg_get_files_list (alpm_pkg_t* pkg);

#endif //!ALPM_UTIL_H
