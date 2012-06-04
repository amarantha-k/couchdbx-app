#! /usr/bin/env ruby
#
# This script makes the Couchbase Server binaries self-contained by locating all nonstandard
# external dynamic library dependencies, copying those libraries into "lib/", and fixing up the
# imports to point to the copied libraries.
#
# It must be called with the cwd set to the root directory of the installation ("couchbase-core").


require "pathname"

LibraryDir = Pathname.new("lib")
BinDir = Pathname.new("bin")
CouchDBBinDir = Pathname.new("lib/couchdb/bin")

# Returns the libraries imported by the binary at 'path', as an array of Pathnames.
def get_imports (path)
  imports = []
  for line in `otool -L '#{path}'`
    if line =~ /^\t(.*)\s*\(.*\)$/
      import = Pathname.new($1.rstrip)
      if import.basename != path.basename
        imports << import
      end
    end
  end
  return imports
end


# Edits the binary at 'libpath' to change its import of 'import' to 'newimport'.
def change_import (libpath, import, newimport)
  return  if newimport == import
  puts "\tChange import #{import} to #{newimport}"
  unless system("install_name_tool", "-change", import, newimport, libpath)
    fail "install_name_tool failed"
  end
end


# Copies a library from 'src' into 'lib/', and recursively processes its imports.
def copy_lib (src, loaded_from)
  return src  if src.to_s.start_with?("lib/")

  dst = LibraryDir + src.basename
  if dst.exist?  # already been copied
    return dst
  end

  if src.dirname.to_s == "@loader_path"
    src = loaded_from.dirname + src.basename
  end
  fail "bad path #{src}"  unless src.absolute?

  puts "\tCopying #{src} --> #{dst}"
  unless system("cp", src, dst)
    fail "cp failed on #{src}"
  end
  dst.chmod(0644)  # Make it writable so we can change its imports

  process(dst, src)
  return dst
end


# Fixes up the binary at 'file' by locating external library dependencies and copying those
# libraries to "lib/".
# If 'original_path' is given, it is the path from which 'file' was copied; this is needed
# for resolution of '@loader_path'-relative imports.
def process (file, original_path =nil)
  puts "-- #{file} ..."
  for import in get_imports(file) do
    path = import.to_s
    unless path.start_with?("/usr/lib/") || path.start_with?("/System/")
      dst = copy_lib(import, (original_path || file))
      change_import(file, import, dst)
    end
  end
  puts "\tend #{file}"
end


# Calls process() on every dylib in the directory tree rooted at 'dir'.
def process_libs_in_tree (dir)
  dir.children.each do |file|
    if file.directory?
      process_libs_in_tree file
    elsif (file.extname == ".dylib" || file.extname == ".so") && file.ftype == "file"
      process(file)
    end
  end
end


### OK, here's the main code:

BinDir.children.each do |file|
  if file.ftype == "file" && file.executable?
    process(file)
  end
end

puts ""
CouchDBBinDir.children.each do |file|
  if file.ftype == "file" && file.executable?
    process(file)
  end
end

puts ""
process_libs_in_tree LibraryDir