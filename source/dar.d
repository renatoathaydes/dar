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

    this(in byte[] contents) pure
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
ArHeaderIterator parseArFile(in byte[] file)
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

    // to create the test.a file:
    //     ar r test.a dub.sdl
    auto contents = cast(immutable(byte[])) read("test/test1.a");
    auto ar = parseArFile(contents);

    assert(ar.front.file == "dub.sdl", "file name unexpected: " ~ ar.front.file);
    assert(ar.front.dataStart == 0u, "dataStart unexpected: " ~ ar.front.dataStart.to!string);
    assert(ar.front.size == 167u, "size unexpected: " ~ ar.front.size.to!string);
    ar.popFront;
    assert(ar.empty, "archive is not empty");
}

/// Parse an AR header, assuming the given slice starts from one.
/// 
/// Returns: the next header in the archive.
ArHeader parseArHeader(in byte[] input)
{
    if (input.length < 60)
    {
        throw new ArException("File too short, cannot parse AR header");
    }
    if (input[58 .. 60] != [0x60, 0x0A])
    {
        throw new ArException("Cannot recognize AR header (wrong ending chars)");
    }
    auto file = (cast(string) input[0 .. 16]).strip;
    auto sizeStr = (cast(string) input[48 .. 58]).strip;
    auto size = sizeStr.to!uint;
    auto dataStart = 0u;
    if (file.startsWith("#1/"))
    {
        auto nameSize = file[3 .. $].to!uint;
        // For some reason, the lengths are larger than they should, but names use C-convention and end with \0
        import core.stdc.string : strlen;

        auto end = strlen(cast(const(char*)) input[60 .. 60 + nameSize]);
        file = (cast(string) input[60 .. 60 + end]).strip;
        dataStart = nameSize;
    }

    byte[8] mode = input[40 .. 48];
    return ArHeader(file, 0, 0, 0, mode, size, dataStart);
}
