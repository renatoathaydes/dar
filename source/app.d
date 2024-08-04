import std.stdio : stderr, writeln;
import std.mmfile : MmFile;
import dar : parseArFile, ArException;
import std.algorithm.iteration : each;

int main(string[] args)
{
	scope mfile = new MmFile(args[1]);
	try
	{
		scope ar = parseArFile(cast(const(byte[])) mfile[]);
		ar.each!writeln;
	}
	catch (ArException e)
	{
		stderr.writeln(e);
		return 1;
	}
	return 0;
}
