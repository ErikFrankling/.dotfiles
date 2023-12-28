#!/usr/bin/env fish
set -l i 0
set -l json (curl 'https://wallhaven.cc/api/v1/search?categories=100&purity=100&atleast=3840x2160&topRange=1M&sorting=toplist&order=desc&ai_art_filter=0')

set path "$HOME/.local/share/wall" 

while test -n (ls "$path/*$(echo $json | jq -r ".data.[$i].id")*"); then
	set i (math $i + 1)
end

curl --create-dirs -OJ --output-dir $path (echo $json | jq -r ".data.[$i].path")

sh "$HOME/.dotfiles/scripts/bg-changer.sh" $(find "$path/" -type f -exec ls -t1 {} + | head -1)

#function get_type
#	set file_type (echo $json | jq ".data.[$i].file_type")
#
#if $file_type = *"png"*; then
#	return "png"
#	else 
#	return "jpg"
#	end
#end
