import std.stdio : File, chunks, stderr, writeln;
import dar : parseArFile, ArException;
import std.algorithm.iteration : each;

int main(string[] args)
{
	scope file = File(args[1], "rb");
	try
	{
		scope ar = parseArFile(file);
		ar.each!writeln;
	}
	catch (ArException e)
	{
		stderr.writeln(e);
		return 1;
	}
	return 0;
}
