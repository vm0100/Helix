// ABOUTME: C-ABI wrapper over imara-diff and dissimilar.
// ABOUTME: Exposes line-level diff and character-level diff to Swift via FFI.

use std::os::raw::c_char;
use std::ptr;
use std::slice;

// -- C-ABI types --

#[repr(C)]
pub struct DiffResult {
    pub hunks: *mut DiffHunk,
    pub hunk_count: u32,
}

#[repr(C)]
pub struct DiffHunk {
    pub old_start: u32,
    pub old_count: u32,
    pub new_start: u32,
    pub new_count: u32,
    pub lines: *mut DiffLine,
    pub line_count: u32,
}

/// 0 = equal, 1 = delete, 2 = insert
#[repr(C)]
pub struct DiffLine {
    pub tag: u8,
    pub text: *mut c_char,
    pub text_len: u32,
}

#[repr(C)]
pub struct InlineResult {
    pub chunks: *mut InlineChunk,
    pub chunk_count: u32,
}

/// 0 = equal, 1 = delete, 2 = insert
#[repr(C)]
pub struct InlineChunk {
    pub tag: u8,
    pub text: *mut c_char,
    pub text_len: u32,
}

// -- Helpers --

/// Converts a raw pointer + length to a &str, returning "" on null/invalid UTF-8.
unsafe fn ptr_to_str<'a>(ptr: *const c_char, len: u32) -> &'a str {
    if ptr.is_null() {
        return "";
    }
    let bytes = slice::from_raw_parts(ptr as *const u8, len as usize);
    std::str::from_utf8(bytes).unwrap_or("")
}

/// Allocates a C string copy of a Rust &str on the heap.
fn str_to_c_heap(s: &str) -> (*mut c_char, u32) {
    let len = s.len() as u32;
    let buf = unsafe {
        let ptr = libc_malloc(s.len() + 1) as *mut c_char;
        if !ptr.is_null() {
            ptr::copy_nonoverlapping(s.as_ptr() as *const c_char, ptr, s.len());
            *ptr.add(s.len()) = 0; // null terminator
        }
        ptr
    };
    (buf, len)
}

// Minimal malloc/free wrappers to avoid depending on libc crate
extern "C" {
    #[link_name = "malloc"]
    fn libc_malloc(size: usize) -> *mut u8;
    #[link_name = "free"]
    fn libc_free(ptr: *mut u8);
}

// -- Line-level diff --

#[no_mangle]
pub unsafe extern "C" fn helix_diff_lines(
    old_ptr: *const c_char,
    old_len: u32,
    new_ptr: *const c_char,
    new_len: u32,
    context_lines: u32,
) -> *mut DiffResult {
    let old_str = ptr_to_str(old_ptr, old_len);
    let new_str = ptr_to_str(new_ptr, new_len);

    let old_lines: Vec<&str> = old_str.lines().collect();
    let new_lines: Vec<&str> = new_str.lines().collect();

    // InternedInput is re-exported at crate root in v0.2.0
    let input = imara_diff::InternedInput::new(old_str, new_str);
    let mut diff = imara_diff::Diff::compute(imara_diff::Algorithm::Histogram, &input);
    diff.postprocess_lines(&input);

    let ctx = context_lines as usize;
    let raw_hunks: Vec<imara_diff::Hunk> = diff.hunks().collect();

    // Build output hunks with context
    let mut out_hunks: Vec<DiffHunk> = Vec::new();

    for hunk in &raw_hunks {
        let before_start = hunk.before.start as usize;
        let before_end = hunk.before.end as usize;
        let after_start = hunk.after.start as usize;
        let after_end = hunk.after.end as usize;

        // Context window around this hunk
        let ctx_old_start = before_start.saturating_sub(ctx);
        let ctx_old_end = (before_end + ctx).min(old_lines.len());
        let ctx_new_start = after_start.saturating_sub(ctx);
        let ctx_new_end = (after_end + ctx).min(new_lines.len());

        let mut lines: Vec<DiffLine> = Vec::new();

        // Leading context (from old side)
        for i in ctx_old_start..before_start {
            let (ptr, len) = str_to_c_heap(old_lines[i]);
            lines.push(DiffLine { tag: 0, text: ptr, text_len: len });
        }

        // Deletions
        for i in before_start..before_end {
            let (ptr, len) = str_to_c_heap(old_lines[i]);
            lines.push(DiffLine { tag: 1, text: ptr, text_len: len });
        }

        // Insertions
        for i in after_start..after_end {
            let (ptr, len) = str_to_c_heap(new_lines[i]);
            lines.push(DiffLine { tag: 2, text: ptr, text_len: len });
        }

        // Trailing context (from old side)
        for i in before_end..ctx_old_end {
            let (ptr, len) = str_to_c_heap(old_lines[i]);
            lines.push(DiffLine { tag: 0, text: ptr, text_len: len });
        }

        let line_count = lines.len() as u32;
        let lines_ptr = vec_to_heap(lines);

        out_hunks.push(DiffHunk {
            old_start: ctx_old_start as u32,
            old_count: (ctx_old_end - ctx_old_start) as u32,
            new_start: ctx_new_start as u32,
            new_count: (ctx_new_end - ctx_new_start) as u32,
            lines: lines_ptr,
            line_count,
        });
    }

    let hunk_count = out_hunks.len() as u32;
    let hunks_ptr = vec_to_heap(out_hunks);

    let result = Box::new(DiffResult {
        hunks: hunks_ptr,
        hunk_count,
    });
    Box::into_raw(result)
}

// -- Character-level diff --

#[no_mangle]
pub unsafe extern "C" fn helix_diff_chars(
    old_ptr: *const c_char,
    old_len: u32,
    new_ptr: *const c_char,
    new_len: u32,
) -> *mut InlineResult {
    let old_str = ptr_to_str(old_ptr, old_len);
    let new_str = ptr_to_str(new_ptr, new_len);

    let chunks = dissimilar::diff(old_str, new_str);

    let mut out_chunks: Vec<InlineChunk> = Vec::new();
    for chunk in &chunks {
        let (tag, text) = match chunk {
            dissimilar::Chunk::Equal(s) => (0u8, *s),
            dissimilar::Chunk::Delete(s) => (1u8, *s),
            dissimilar::Chunk::Insert(s) => (2u8, *s),
        };
        let (ptr, len) = str_to_c_heap(text);
        out_chunks.push(InlineChunk { tag, text: ptr, text_len: len });
    }

    let chunk_count = out_chunks.len() as u32;
    let chunks_ptr = vec_to_heap(out_chunks);

    let result = Box::new(InlineResult {
        chunks: chunks_ptr,
        chunk_count,
    });
    Box::into_raw(result)
}

// -- Memory deallocation --

#[no_mangle]
pub unsafe extern "C" fn helix_diff_free(ptr: *mut DiffResult) {
    if ptr.is_null() { return; }
    let result = Box::from_raw(ptr);
    if !result.hunks.is_null() {
        let hunks = Vec::from_raw_parts(result.hunks, result.hunk_count as usize, result.hunk_count as usize);
        for hunk in hunks {
            if !hunk.lines.is_null() {
                let lines = Vec::from_raw_parts(hunk.lines, hunk.line_count as usize, hunk.line_count as usize);
                for line in lines {
                    if !line.text.is_null() {
                        libc_free(line.text as *mut u8);
                    }
                }
            }
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn helix_inline_free(ptr: *mut InlineResult) {
    if ptr.is_null() { return; }
    let result = Box::from_raw(ptr);
    if !result.chunks.is_null() {
        let chunks = Vec::from_raw_parts(result.chunks, result.chunk_count as usize, result.chunk_count as usize);
        for chunk in chunks {
            if !chunk.text.is_null() {
                libc_free(chunk.text as *mut u8);
            }
        }
    }
}

// -- Utility --

/// Moves a Vec's contents to a heap allocation and returns a raw pointer.
/// The Vec is consumed; caller must free with Vec::from_raw_parts + drop.
fn vec_to_heap<T>(mut v: Vec<T>) -> *mut T {
    if v.is_empty() {
        return ptr::null_mut();
    }
    let ptr = v.as_mut_ptr();
    std::mem::forget(v);
    ptr
}

// -- Tests --

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn line_diff_basic() {
        let old = "hello\nworld\n";
        let new = "hello\nrust\n";

        unsafe {
            let result = helix_diff_lines(
                old.as_ptr() as *const c_char, old.len() as u32,
                new.as_ptr() as *const c_char, new.len() as u32,
                3,
            );
            assert!(!result.is_null());

            let r = &*result;
            assert!(r.hunk_count > 0);

            // Check first hunk has lines
            let first_hunk = &*r.hunks;
            assert!(first_hunk.line_count > 0);

            helix_diff_free(result);
        }
    }

    #[test]
    fn char_diff_basic() {
        let old = "hello world";
        let new = "hello rust";

        unsafe {
            let result = helix_diff_chars(
                old.as_ptr() as *const c_char, old.len() as u32,
                new.as_ptr() as *const c_char, new.len() as u32,
            );
            assert!(!result.is_null());

            let r = &*result;
            assert!(r.chunk_count > 0);

            // First chunk should be "hello " (equal)
            let first = &*r.chunks;
            assert_eq!(first.tag, 0); // equal

            helix_inline_free(result);
        }
    }

    #[test]
    fn line_diff_identical() {
        let text = "same\ncontent\n";

        unsafe {
            let result = helix_diff_lines(
                text.as_ptr() as *const c_char, text.len() as u32,
                text.as_ptr() as *const c_char, text.len() as u32,
                3,
            );
            assert!(!result.is_null());

            let r = &*result;
            assert_eq!(r.hunk_count, 0);

            helix_diff_free(result);
        }
    }

    #[test]
    fn line_diff_empty_inputs() {
        let empty = "";
        let text = "hello\n";

        unsafe {
            let result = helix_diff_lines(
                empty.as_ptr() as *const c_char, 0,
                text.as_ptr() as *const c_char, text.len() as u32,
                3,
            );
            assert!(!result.is_null());

            let r = &*result;
            assert!(r.hunk_count > 0);

            helix_diff_free(result);
        }
    }

    #[test]
    fn free_null_pointers() {
        // Should not crash
        unsafe {
            helix_diff_free(ptr::null_mut());
            helix_inline_free(ptr::null_mut());
        }
    }
}
