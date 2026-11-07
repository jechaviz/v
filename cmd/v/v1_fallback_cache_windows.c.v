// Copyright (c) 2019-2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module main

import crypto.rand
import os

#include "@VMODROOT/cmd/v/v1_fallback_cache_windows_helpers.h"

fn C.v1_fallback_create_private_directory(const_path &u16) int

// Reuse the normal Windows user cache when HOME is absent. Keep the random
// private temporary fallback for hosts without a safe persistent directory.
fn v1_fallback_windows_user_cache_parent() ?string {
	local_app_data := os.getenv('LOCALAPPDATA').trim_space()
	if local_app_data == '' {
		return none
	}
	candidate := os.abs_path(os.join_path(local_app_data, 'v', 'v1-fallback-private'))
	os.mkdir_all(os.dir(candidate)) or { return none }
	wide_path := candidate.replace('/', '\\').to_wide()
	created := C.v1_fallback_create_private_directory(wide_path)
	unsafe { free(voidptr(wide_path)) }
	if created == 0 {
		return none
	}
	entry := open_tool_cache_entry_dir(candidate) or { return none }
	defer {
		entry.close()
	}
	if !tool_cache_root_can_stage(candidate) {
		return none
	}
	return candidate
}

fn v1_fallback_private_windows_temp_cache_parent(temp_root string) !string {
	for _ in 0 .. 64 {
		random_suffix := rand.bytes(16) or {
			return error('could not generate a private V1 fallback cache name: ${err}')
		}
		candidate := os.join_path(temp_root, 'v1-fallback-cache-${random_suffix.hex()}')
		wide_path := candidate.replace('/', '\\').to_wide()
		created := C.v1_fallback_create_private_directory(wide_path)
		unsafe { free(voidptr(wide_path)) }
		if created == 2 {
			continue
		}
		if created == 0 {
			return error('could not create a private V1 fallback cache at `${candidate}`')
		}
		entry := open_tool_cache_entry_dir(candidate) or {
			return error('refusing unsafe V1 fallback cache path `${candidate}`: ${err}')
		}
		defer { entry.close() }
		if !tool_cache_root_can_stage(candidate) {
			return error('refusing unsafe V1 fallback cache path `${candidate}`: expected a private user-owned directory')
		}
		return candidate
	}
	return error('could not reserve a unique private V1 fallback cache in `${temp_root}`')
}
