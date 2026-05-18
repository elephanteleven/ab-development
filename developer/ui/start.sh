for PATH_DIR_UI in $(ls | grep -Evw "web|start.sh|plugins" | awk '{print "./"$1}' & ls ./plugins | awk '{print "./plugins/"$1}' & wait); do
   npm run --prefix $PATH_DIR_UI watch &
done
wait
