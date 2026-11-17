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
      if [[ "$dir" == "developer/web" ]]; then
         # `npm run watch` in each UI repo builds into developer/web/assets, the web
         # repo's tracked copy. Drop that output before the stash, so the stash keeps
         # only real edits and the pull meets a clean assets/; the watchers write it
         # again.
         (cd ./$dir && rm -rf ./assets && git checkout -- assets)
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
         developer/web)
            CHANGING_TO_BRANCH=develop
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
      if [[ "$dir" != "." && -f ./$dir/.gitmodules ]]; then
         # Nested submodules follow the commits their parent records: AppBuilder
         # (platform_service) and AppBuilder/core (class_core) in the services, the
         # class_core copy in ab_platform_web and pwa.
         (cd ./$dir && git submodule update --init --recursive)
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
      if [[ -f ./$dir/AppBuilder/package.json ]]; then
         # platform_service needs its own node_modules, as in the service images
         # (`npm ci` in /app/AppBuilder). `ci` leaves its files alone, so local edits
         # in AppBuilder survive (this nested repo has no stash).
         env -u npm_config_allow_scripts \
            npm_config_allow_git=all \
            npm ci --prefix ./$dir/AppBuilder
      fi
      if [[ -n "$STASHED" ]]; then
         $CMD_PREFIX stash apply && $CMD_PREFIX stash drop
      fi
   ) &
done
wait
