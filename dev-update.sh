if [[ ! -f ./.env ]]; then
   cp ./example.env .env
   echo "Please configure your parameters in the .env file."
fi
if [[ ! -f ./config/local.js ]]; then
   cp ./config/example.local.js ./config/local.js
   echo "Please configure your parameters in the ./cofig/local.js file."
fi
git submodule init && git submodule update
for dir in "." $(git submodule | awk '{print $2}'); do
   (
      CMD_PREFIX="git --git-dir=./$dir/.git --work-tree=./$dir"
      CURRENT_BRANCH=""
      CHANGING_TO_BRANCH=""
      if [[ "$($CMD_PREFIX status | awk '{print $1}')" != "HEAD" ]]; then
         CURRENT_BRANCH=$($CMD_PREFIX branch | grep "\*" | awk '{print $2}')
      fi
      $CMD_PREFIX stash
      case $dir in
         developer/services/web)
            rm -rf developer/services/web/assets
            $CMD_PREFIX add .
            $CMD_PREFIX reset .
            $CMD_PREFIX restore .
            $CMD_PREFIX checkout master
            $CMD_PREFIX pull
            rm developer/services/web/assets/*
            rm developer/services/web/assets/tenant/default/AB*
            rm developer/services/web/assets/tenant/default/HR*
            rm -rf developer/ui/web/assets
            cp -r developer/services/web/assets developer/ui/web
            $CMD_PREFIX add .
            $CMD_PREFIX reset .
            $CMD_PREFIX restore .
            CHANGING_TO_BRANCH=develop
            ;;
         developer/components/class_core)
            CHANGING_TO_BRANCH=v2
            ;;
         *)
            CHANGING_TO_BRANCH=master
            ;;
      esac
      $CMD_PREFIX checkout $CHANGING_TO_BRANCH
      $CMD_PREFIX pull
      $CMD_PREFIX checkout $CURRENT_BRANCH
      if [[ -f ./$dir/package.json ]]; then
         npm install --prefix ./$dir -f
         $CMD_PREFIX add .
         $CMD_PREFIX reset .
         $CMD_PREFIX restore .
      fi
      $CMD_PREFIX stash apply
      $CMD_PREFIX stash drop
   ) &
done
wait
