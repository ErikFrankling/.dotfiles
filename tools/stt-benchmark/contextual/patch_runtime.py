"""Apply explicit, version-checked integration to the pinned audio.cpp source."""
from pathlib import Path
p=Path('src/models/vibevoice_asr/session.cpp');s=p.read_text()
def replace(old,new):
 global s
 if s.count(old)!=1: raise RuntimeError(f'Expected one integration point: {old[:90]}')
 s=s.replace(old,new)
replace('#include <ggml.h>', '#include <ggml.h>\n#include "phrase_bias.h"\n#include <sstream>')
replace('    bool compare_bf16) {\n    if (logits.empty()) {', '    bool compare_bf16,\n    const std::vector<double> & bias = {}) {\n    if (logits.empty()) {')
replace('TokenLogProb candidate{static_cast<int32_t>(i), value};','TokenLogProb candidate{static_cast<int32_t>(i), value + (bias.empty() ? 0.0 : bias.at(i))};')
# The original logits still supply the denominator; the contextual score is
# NOT renormalized per beam, which would break prefix rollback accounting.
helper='''
stt_context::PhraseBias make_phrase_bias(const VibeVoiceASRRequest &request,
                                       const VibeVoiceASRTextTokenizer &tokenizer) {
    std::vector<std::vector<int32_t>> phrases;
    std::istringstream lines(request.bias_phrases);
    std::string line;
    while(std::getline(lines,line)) {
        if(line.empty()) continue;
        if(line.size()>256 || line.find_first_of("\\\"{}[]\\\\")!=std::string::npos)
            throw std::runtime_error("bias phrases must be plain names, max 256 bytes");
        phrases.push_back(tokenizer.encode(line));
        phrases.push_back(tokenizer.encode(" "+line));
        if(phrases.size()>800) throw std::runtime_error("at most 400 bias phrases supported");
    }
    return stt_context::PhraseBias(std::move(phrases),request.bias_weight);
}

bool in_transcript_string(const std::string &text) {
    // Bias only spoken Content/text values, never timestamps or speaker IDs.
    bool quoted=false, escaped=false, expecting_value=false, spoken=false;
    std::string value, key;
    for(char c:text) {
        if(quoted) {
            if(escaped){ escaped=false; value+=c; continue; }
            if(c=='\\\\'){escaped=true;continue;}
            if(c=='"'){quoted=false; if(!expecting_value) key=value;
                else {expecting_value=false; key.clear();} spoken=false;}
            else value+=c;
        } else if(c=='"') {quoted=true;value.clear();spoken=expecting_value&&(key=="Content"||key=="text");}
        else if(c==':') expecting_value=true;
        else if(c==','||c=='}'||c==']'){expecting_value=false;key.clear();}
    }
    return quoted&&spoken;
}

std::vector<double> phrase_deltas(const stt_context::PhraseBias &bias,
                                 const VibeVoiceASRTextTokenizer &tokenizer,
                                 const std::vector<int32_t>& generated, size_t vocab,
                                 double weight) {
    if(weight==0 || !in_transcript_string(tokenizer.decode(generated,true))) return {};
    return bias.deltas(generated,vocab);
}
'''
replace('int32_t sample_token(',helper+'\nint32_t sample_token(')
replace('    VibeVoiceASRRequest out;','''    VibeVoiceASRRequest out;
    if (const auto value = runtime::find_option(request.options, {"bias_phrases"})) out.bias_phrases=*value;
    if (const auto value = runtime::parse_float_option(request.options, {"bias_weight"})) out.bias_weight=*value;
    if(out.bias_weight!=0 && is_streaming_family(*assets_))
        throw std::runtime_error("phrase bias currently supports offline final recognition only");''')
replace('    VibeVoiceDecoderCachedState state;\n    text_decoder_.reset_cached_state(state, std::move(prefill.state));','    const auto phrase_bias = make_phrase_bias(request,tokenizer_);\n    VibeVoiceDecoderCachedState state;\n    text_decoder_.reset_cached_state(state, std::move(prefill.state));')
# Scope to offline generation: streaming has a similar decoder loop.
pos=s.index('std::vector<int32_t> VibeVoiceASRSession::generate_greedy_or_sample(')
a,b=s[:pos],s[pos:]
needle='        const int32_t next = request.generation.temperature > 0.0F'
assert b.count(needle)==1
b=b.replace(needle,'''        const auto bias=phrase_deltas(phrase_bias,tokenizer_,generated,logits.size(),request.bias_weight);
        for(size_t i=0;i<bias.size();++i) logits[i]+=static_cast<float>(bias[i]);
'''+needle)
s=a+b
replace('    const int64_t beam_count = request.generation.num_beams;', '    const auto phrase_bias = make_phrase_bias(request,tokenizer_);\n    const int64_t beam_count = request.generation.num_beams;')
replace('            for (const auto & item : top_log_probs(logits, per_beam_candidates, greedy_compare_bf16_)) {','''            const auto bias=phrase_deltas(phrase_bias,tokenizer_,beams[parent_index].generated,logits.size(),request.bias_weight);
            for (const auto & item : top_log_probs(logits, per_beam_candidates, greedy_compare_bf16_,bias)) {''')
p.write_text(s)
p=Path('include/engine/models/vibevoice_asr/types.h');s=p.read_text();s=s.replace('    std::string context;', '    std::string context;\n    std::string bias_phrases;\n    float bias_weight = 0.0F;');p.write_text(s)
