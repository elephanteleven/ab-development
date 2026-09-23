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
      # Only restore later if this stash actually creates an entry. Without the
      # count check, the `stash apply`/`stash drop` at the end run unconditionally:
      # they error on every clean repo, and on a repo that has a PRE-EXISTING stash
      # they apply that unrelated stash and then permanently delete it.
      STASH_BEFORE=$($CMD_PREFIX stash list | wc -l)
      $CMD_PREFIX stash
      STASH_AFTER=$($CMD_PREFIX stash list | wc -l)
      STASHED=""
      if [[ "$STASH_AFTER" -gt "$STASH_BEFORE" ]]; then
         STASHED=1
      fi
      case $dir in
         developer/services/web)
            rm -rf developer/services/web/assets
            $CMD_PREFIX add .
            $CMD_PREFIX reset .
            $CMD_PREFIX restore .
            $CMD_PREFIX checkout master
            $CMD_PREFIX pull
            # No -rf, deliberately. This clears the built bundles and index.html at
            # the top level while the asset subdirectories survive -- rm reports
            # "Is a directory" for each, which is expected and can be ignored. Those
            # directories are exactly what the cp below puts into
            # developer/ui/web/assets; -rf here would delete them and break it.
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
         .)
            # The superproject tracks `main`; it has no `master` branch, so the
            # default below would fail here with "pathspec 'master' did not match".
            CHANGING_TO_BRANCH=$CURRENT_BRANCH
            ;;
         *)
            CHANGING_TO_BRANCH=master
            ;;
      esac
      if [[ -n "$CHANGING_TO_BRANCH" ]]; then
         $CMD_PREFIX checkout $CHANGING_TO_BRANCH
         $CMD_PREFIX pull
      fi
      if [[ -n "$CURRENT_BRANCH" ]]; then
         $CMD_PREFIX checkout $CURRENT_BRANCH
      fi
      if [[ -f ./$dir/package.json ]]; then
         # npm 12: `npm run` exports config to children AS command-line flags, and
         # npm rejects --allow-scripts on any local install -- so an allow-scripts
         # entry in ANY npmrc makes this install die with EALLOWSCRIPTS. Clearing the
         # inherited variable lets npm read allow-scripts from npmrc normally.
         # allow-git is set explicitly because npm 12 defaults it to "none", which
         # refuses the github:CruGlobal/ab-utils dependency 11 services declare.
         env -u npm_config_allow_scripts \
            npm_config_allow_git=all \
            npm install --prefix ./$dir -f
         $CMD_PREFIX add .
         $CMD_PREFIX reset .
         $CMD_PREFIX restore .
      fi
      if [[ -n "$STASHED" ]]; then
         $CMD_PREFIX stash apply && $CMD_PREFIX stash drop
      fi
   ) &
done
wait
