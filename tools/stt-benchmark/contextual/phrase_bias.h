#pragma once
// Experimental contextual shallow fusion. This is not a reproduction of LOGIC.
// Scores are added AFTER the acoustic model's log-softmax. Incomplete prefix
// bonuses are revoked on mismatch; completed phrases retain their bonus.
#include <algorithm>
#include <cstdint>
#include <map>
#include <stdexcept>
#include <vector>
#include <cmath>

namespace stt_context {
class PhraseBias {
    std::vector<std::vector<int32_t>> phrases_;
    double weight_;
public:
    PhraseBias(std::vector<std::vector<int32_t>> phrases, double weight)
        : phrases_(std::move(phrases)), weight_(weight) {
        if (!std::isfinite(weight) || weight < 0 || weight > 3)
            throw std::runtime_error("phrase bias weight must be finite and between 0 and 3");
        std::sort(phrases_.begin(), phrases_.end());
        phrases_.erase(std::unique(phrases_.begin(), phrases_.end()), phrases_.end());
        for (const auto &p : phrases_) if(p.empty() || p.size()>64)
            throw std::runtime_error("phrase bias supports 1 to 64 tokens per phrase");
    }
    std::vector<double> deltas(const std::vector<int32_t>& history, size_t vocab) const {
        if(weight_ == 0 || phrases_.empty()) return {};
        size_t depth=0;
        std::map<int32_t,size_t> advances, completions;
        for(const auto &phrase : phrases_) {
            // Every matching suffix matters, including overlapping prefixes.
            for(size_t n=0; n<phrase.size() && n<=history.size(); ++n) {
                if(n && !std::equal(phrase.begin(),phrase.begin()+n,history.end()-n)) continue;
                depth=std::max(depth,n);
                auto token=phrase[n];
                if(token<0 || static_cast<size_t>(token)>=vocab)
                    throw std::runtime_error("phrase token outside decoder vocabulary");
                if(n+1==phrase.size()) completions[token]=std::max(completions[token],n+1);
                else advances[token]=std::max(advances[token],n+1);
            }
        }
        std::vector<double> result(vocab,-weight_*depth);
        for(const auto &[token,next] : advances) result[token]+=weight_*next;
        for(const auto &[token,bonus] : completions) result[token]+=weight_*bonus;
        return result;
    }
};
}
