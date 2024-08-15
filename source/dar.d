/// DAR - D Ar Archive Parser.
///
/// To parse an AR archive, use `parseArFile`.
/// That returns an `InputRange` of `ArHeader`s, providing each file header in the archive.
module dar;

import std.mmfile : MmFile;
import std.conv : to;
import std.string : strip, startsWith;
import std.range : empty;
import std.functional : unaryFun;
import std.typecons : Nullable;

private alias isEven = unaryFun!("(a & 1) == 0");

/// File header in the AR archive.
struct ArHeader
{
    /// File name.
    string file;
    /// File modification timestamp (in seconds).
    ulong mod;
    /// Owner ID.
    uint owner;
    /// Group ID.
    uint group;
    /// File mode (type and permission).
    byte[8] mode;
    /// File size in bytes.
    uint size;
    /// In some cases, the real file name is included in the data section.
    /// If that's the case, this value will be greater than 0 and indicates where the actual data starts.
    uint dataStart;
}

/// Iterator over the `ArHeader`s in an AR archive.
final class ArHeaderIterator
{

    private Nullable!ArHeader current;
    private const(byte)[] contents;
    private uint index;

    this(const byte[] contents) pure
    {
        this.contents = contents;
    }

    /// Check if this iterator is empty.
    bool empty() const @nogc => contents.empty;

    private void next()
    {
        try
        {
            current = parseArHeader(contents);
        }
        catch (ArException e)
        {
            throw e.withPrefix("at " ~ index.to!string ~ ": ");
        }
    }

    /// Pop the front element of this iterator.
    void popFront()
    {
        auto value = current.get;
        auto entryLen = value.size.isEven ? value.size : value.size + 1;
        auto nextStart = 60 + entryLen;
        index += nextStart;
        contents = contents[nextStart .. $];
        current.nullify;
    }

    /// Get the front element of this iterator.
    ArHeader front()
    {
        if (current.isNull)
            next();
        return current.get;
    }
}

/// Exception thrown in case of an error parsing an AR archive.
class ArException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__,
        Throwable next = null) @nogc @safe pure nothrow
    {
        super(msg, file, line, next);
    }

    ArException withPrefix(string prefix)
    {
        return new ArException(prefix ~ msg, file, line);
    }
}

/// Parse an AR archive.
/// Returns: a `InputRange` over the contents of the AR archive.
ArHeaderIterator parseArFile(const byte[] file)
{
    if (file.length < 7)
    {
        throw new ArException("File is not AR archive, does not start with magic string !<arch>");
    }
    auto magic = cast(string) file[0 .. 8];
    if (magic != "!<arch>\n")
    {
        throw new ArException("File is not AR archive, does not start with magic string !<arch>");
    }
    return new ArHeaderIterator(file[8 .. $]);
}

///
unittest
{
    import std.file : read;
    import std.exception : assumeUnique;

    // to create the test.a file:
    //     ar r test.a dub.sdl
    auto contents = assumeUnique(cast (byte[]) read("test/test1.a"));
    auto ar = parseArFile(contents);
    auto f = ar.front;
    assert(f.file == "dub.sdl", "file name unexpected: " ~ f.file);
    assert(f.mod == 1722788759u, "mod unexpected: " ~ f.mod.to!string);
    assert(f.dataStart == 0u, "dataStart unexpected: " ~ f.dataStart.to!string);
    assert(f.size == 167u, "size unexpected: " ~ f.size.to!string);
    ar.popFront;
    assert(ar.empty, "archive is not empty");
}

/// Parse an AR header, assuming the given slice starts from one.
/// 
/// Returns: the next header in the archive.
ArHeader parseArHeader(const byte[] input)
{
    if (input.length < 60)
    {
        throw new ArException("File too short, cannot parse AR header");
    }
    if (input[58 .. 60] != [0x60, 0x0A])
    {
        throw new ArException("Cannot recognize AR header (wrong ending chars)");
    }
    auto file = (cast(const char[]) input[0 .. 16]).strip;
    auto mod = (cast(const char[]) input[16 .. 16 + 12]).strip.to!ulong;
    auto owner = (cast(const char[]) input[28 .. 28 + 6]).strip.to!uint;
    auto group = (cast(const char[]) input[34 .. 34 + 6]).strip.to!uint;
    auto size = (cast(const char[]) input[48 .. 58]).strip.to!uint;
    auto dataStart = 0u;
    if (file.startsWith("#1/"))
    {
        auto nameSize = file[3 .. $].to!uint;
        // For some reason, the lengths are larger than they should, but names use C-convention and end with \0
        import core.stdc.string : strlen;

        auto end = strlen(cast(const(char*)) input[60 .. 60 + nameSize]);
        file = cast(const(char[])) input[60 .. 60 + end];
        dataStart = nameSize;
    }

    byte[8] mode = input[40 .. 48].dup;
    ArHeader header = {
        file: cast(string) file.dup,
        mod: mod,
        owner: owner,
        group: group,
        mode: mode,
        size: size,
        dataStart: dataStart
    };
    return header;
}
