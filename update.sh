if [[ ! -f ./.env ]]; then
   cp ./example.env .env
   echo "Please configure your parameters in the .env file."
fi
if [[ ! -f ./config/local.js ]]; then
   cp ./config/example.local.js ./config/local.js
   echo "Please configure your parameters in the ./cofig/local.js file."
fi
git submodule init && git submodule update
npm install -f &
for dir in "." $(git submodule | awk '{print $2}'); do
   (
      CMD_PREFIX="git --git-dir=./$dir/.git --work-tree=./$dir"
      CURRENT_BRANCH=""
      if [[ "$($CMD_PREFIX status | awk '{print $1}')" != "HEAD" ]]; then
         CURRENT_BRANCH=$($CMD_PREFIX branch | grep "\*" | awk '{print $2}')
      fi
      $CMD_PREFIX stash
      case $dir in
         developer/services/web)
            $CMD_PREFIX checkout develop
            $CMD_PREFIX pull
            ;;
         developer/components/class_core)
            $CMD_PREFIX checkout v2
            $CMD_PREFIX pull
            ;;
         *)
            $CMD_PREFIX checkout master 
            $CMD_PREFIX pull
            ;;
      esac
      $CMD_PREFIX checkout $CURRENT_BRANCH
      $CMD_PREFIX stash apply
      $CMD_PREFIX stash drop
      if [[ -f ./$dir/package.json ]]; then
         npm install --prefix ./$dir -f
      fi
   ) &
done
wait
