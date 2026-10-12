#!/usr/bin/env python3
"""Compile and exercise the RN dependency's real native highlighter against shared fixtures.
Run from any directory; the sibling legend-apps checkout must have dependencies installed.
This is a correctness check, not a timed benchmark. Outputs stay under .build.
"""
from pathlib import Path
import subprocess,json,concurrent.futures,os,sys
here=Path(__file__).resolve().parent
repo=here.parent.parent
src=(repo/'../legend-apps/apps/chat-history/node_modules/react-native-enriched-markdown/cpp/highlight').resolve()
out=repo/'.build/chat-history-benchmarks/syntax-check';out.mkdir(parents=True,exist_ok=True)
external='--builtin' not in sys.argv
langs=json.loads((repo/'../legend-apps/apps/chat-history/scripts/benchmark-markdown.json').read_text())['codeHighlightLanguages']
subprocess.run(['node',str(src/'gen-registry.mjs'),'--vendor-dir',str(src/'vendor'),'--languages',','.join(langs),'--out',str(out)],check=True)
fixtures=json.loads((here/'syntax-highlighting-fixtures.json').read_text())
body='''#include "CodeBlockHighlighter.hpp"
#include "CodeBlockLanguages.hpp"
#include "HighlightGrammars.hpp"
#include <tree_sitter/api.h>
#include <cstring>
#include <iostream>
int main() { int failures = 0;
'''
for f in fixtures:
 body+='''{ std::string source = SOURCE; std::string language = LANGUAGE;
 const auto* grammar=Markdown::findGrammar(Markdown::canonicalGrammarId(language).c_str());
 uint32_t offset=0; TSQueryError error=TSQueryErrorNone;
 auto* query=ts_query_new(grammar->language(), grammar->highlightsQuery, strlen(grammar->highlightsQuery), &offset, &error);
 auto tokens=Markdown::highlightCode(source, language);
 bool colored=false; for (auto t:tokens) { int k=(int)t.type; if(k!=1 && k!=2 && k!=9 && k!=13) colored=true; }
 std::cout << language << " tokens=" << tokens.size() << " colored=" << colored << " queryError=" << error << " at=" << offset << std::endl;
 if(!query || tokens.empty() || !colored) failures++;
 if(query) ts_query_delete(query);
 }
'''.replace('SOURCE',json.dumps(f['source'],ensure_ascii=False)).replace('LANGUAGE',json.dumps(f['language']))
body += 'if (!Markdown::highlightCode(std::string(51201, \'x\'), "js").empty()) failures++;\n'
body += 'if (!Markdown::highlightCode(std::string(2000, \'\\n\'), "js").empty()) failures++;\n'
body += 'if (!Markdown::highlightCode("const x = 42;", "unknown").empty()) failures++;\n'
body+='return failures ? 1 : 0; }\n';(out/'main.cpp').write_text(body)
files=[src/'vendor/tree-sitter/src/lib.c']
for lang in ([] if external else langs):
 files += [p for p in (src/'vendor/grammars'/lang).glob('*.c') if p.name in ['parser.c','scanner.c']]
files += [src/'CodeBlockHighlighter.cpp',src/'CodeBlockLanguages.cpp',(src/'ExternalGrammarRegistry.cpp' if external else out/'generated_registry.cpp'),out/'main.cpp']
def compile(pair):
 i,p=pair;obj=out/(p.parent.name+'-'+p.name+'.o'); inc=[src,src/'vendor/tree-sitter/include',src/'vendor/tree-sitter/src',src/'vendor/grammars'/p.parent.name,p.parent,out];cpp=p.suffix=='.cpp'
 command=['clang++' if cpp else 'clang','-std=c++20' if cpp else '-std=c11','-O0','-w','-DENRICHED_MARKDOWN_CODE_HIGHLIGHT',*(['-DENRICHED_MARKDOWN_EXTERNAL_GRAMMARS'] if external else []),'-D_DEFAULT_SOURCE','-c',str(p),'-o',str(obj)]+[f'-I{x}' for x in inc]

 if not obj.exists() or obj.stat().st_mtime < p.stat().st_mtime: subprocess.run(command,check=True)
 return str(obj)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool: objs=list(pool.map(compile,enumerate(files)))
subprocess.run(['clang++',*objs,'-o',str(out/'check')],check=True)
r=subprocess.run([str(out/'check')],text=True,capture_output=True,env={**os.environ, 'BENCHMARK_GRAMMAR_ROOT':str(repo/'.build/chat-history-benchmarks/grammar-packs/v1')});(out/'result.txt').write_text(r.stdout);print(r.stdout);raise SystemExit(r.returncode)
