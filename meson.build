project('pamac', 'c', 'vala',
		default_options : [
		'prefix=/usr',
		'sysconfdir=/etc',],
		version : '11.7.3')

# jemalloc option handling
jemalloc_opt = get_option('jemalloc')
if jemalloc_opt == 'true'
  jemalloc = dependency('jemalloc', required: true)
  use_jemalloc = true
elif jemalloc_opt == 'auto'
  jemalloc = dependency('jemalloc', required: false)
  use_jemalloc = jemalloc.found()
else
  jemalloc = dependency('', required: false)
  use_jemalloc = false
endif

subdir('resources')
subdir('src')
subdir('data')
