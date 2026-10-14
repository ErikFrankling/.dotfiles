#include "phrase_bias.h"
#include <cassert>
#include <iostream>
int main(){
 using stt_context::PhraseBias;
 PhraseBias p({{1,2,3},{1,2,3}},1);
 assert(p.deltas({},8)[1]==1);
 assert(p.deltas({1},8)[2]==1);
 assert(p.deltas({1,2},8)[3]==1);
 assert(p.deltas({1,2},8)[7]==-2); // discarded partial: net zero bonus
 assert(p.deltas({1,2,3},8)[7]==0); // completed phrase keeps its reward
 PhraseBias overlap({{1,1,2},{1,3}},.5);
 assert(overlap.deltas({1,1},8)[2]==.5);
 assert(overlap.deltas({1,1},8)[3]==0);
 assert(PhraseBias({{1}},0).deltas({},8).empty());
 assert(PhraseBias({{1}},1).deltas({1},8)[1]==1);
 PhraseBias repeated({{1,1}},1);
 double total=0;std::vector<int32_t> h;
 for(int token:{1,1,1,7}){total+=repeated.deltas(h,8)[token];h.push_back(token);}
 assert(total==4); // two overlapping completed phrases; unfinished suffix revoked
 bool failed=false;try{PhraseBias({{1}},NAN);}catch(...){failed=true;}assert(failed);
 std::cout<<"phrase bias: rollback, completion, overlap, deduplication and disabled control passed\n";
}
