import sys
import re

# http://stackoverflow.com/questions/241327/python-snippet-to-remove-c-and-c-comments
def comment_remover(text):
    def replacer(match):
        s = match.group(0)
        if s.startswith('/'):
            return ""
        else:
            return s
    pattern = re.compile(
        r'//.*?$|/\*.*?\*/|\'(?:\\.|[^\\\'])*\'|"(?:\\.|[^\\"])*"',
        re.DOTALL | re.MULTILINE
    )
    return re.sub(pattern, replacer, text)

def decomment_cpp(text):
    dtext = comment_remover(text)
    lines = dtext.split("\n")
    outlines = []
    for line in lines:
        if not len(line.strip()) == 0:
            outlines.append(line)
    return "\n".join(outlines)

def decomment_lua(text):
    lines = text.split("\n")
    outlines = []
    for line in lines:
        if not line.strip().startswith("--") and not len(line.strip()) == 0:
            outlines.append(line)
    return "\n".join(outlines)

usage = "usage: infile outfile [lua|cpp]"
if __name__ == "__main__":
    if len(sys.argv) != 4:
        print usage
        sys.exit(1)
    infile = open(sys.argv[1], "r")
    text = infile.read()
    infile.close()
    decommented_text = ""
    if sys.argv[3] == "cpp":
        decommented_text = decomment_cpp(text)
    elif sys.argv[3] == "lua":
        decommented_text = decomment_lua(text)
    else:
        print usage
    outfile = open(sys.argv[2], "w")
    outfile.write(decommented_text)
    outfile.close()
