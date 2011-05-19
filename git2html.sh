#! /bin/bash

# git2html - Convert a git repository to a set of static HTML pages.
# Copyright (c) 2011 Neal H. Walfield <neal@walfield.org>
#
# git2html is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# git2html is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -e
# set -x

PROJECT="Woodchuck"
# Directory containing the repository.
REPOSITORY=/home/neal/public_html/woodchuck.git

PUBLIC_REPOSITORY="http://hssl.cs.jhu.edu/~neal/woodchuck.git"
# Where to create the html pages.
TARGET=/home/neal/public_html/woodchuck/src
# List of branches for which html pages should be created.
BRANCHES="master release-0.1"

if test ! -d "$REPOSITORY"
then
  echo "Repository $REPOSITORY does not exists.  Misconfiguration likely."
  exit 1
fi

# Make the file pretty (on stdout).  Don't make the output commit or
# branch specific!  The same html is shared among all files with the
# same content.
#
# Arguments: "branch" "commit" "directory-root" "relative-filename" "hash"
pretty_print()
{
  branch="$1"
  commit="$2"
  directory="$3"
  filename="$4"
  hash="$5"

  echo "<html><head></head>"
  echo "<body><pre>"
  git show "$hash" | awk '{ ++line; printf("%5d: %s\n", line, $0); }'
  echo "</pre></body></html>"
}

mkdir -p "$TARGET"
if test ! -d "$TARGET/objects"
then
  mkdir "$TARGET/objects"
fi

if test ! -e "$TARGET/commits"
then
  mkdir "$TARGET/commits"
fi

if test ! -e "$TARGET/branches"
then
  mkdir "$TARGET/branches"
fi


# Clone the repository
git clone $REPOSITORY "$TARGET/repository"

# For each branch and each commit create and extract an archive of the form
#   $TARGET/commits/$commit
#
# and a link:
#
#   $TARGET/branches/$commit -> $TARGET/commits/$commit

# Count the number of branch we want to process to improve reporting.
bcount=0
for branch in $BRANCHES
do
  let ++bcount
done

INDEX="$TARGET/index.html"

echo "<html><head><title>$PROJECT</title></head>" \
  "<body>" \
  "<h2>$PROJECT</h2>" \
  "<h3>Repository</h3>" \
  "Clone this repository using:" \
  "<pre>" \
  " git clone $PUBLIC_REPOSITORY" \
  "</pre>" \
  "<h3>Branches</h3>" \
  "<ul>" \
  > "$INDEX"

b=0
for branch in $BRANCHES
do
  let ++b

  cd "$REPOSITORY"

  # Count the number of commits on this branch to improve reporting.
  ccount=$(git rev-list $branch | wc -l)

  echo "Branch $branch ($b/$bcount): processing ($ccount commits)."

  BRANCH_INDEX="$TARGET/branches/$branch.html"

  c=0
  git rev-list --topo-order $branch | while read commit
  do
    let ++c
    COMMIT_BASE="$TARGET/commits/$commit"
    if test -e "$COMMIT_BASE"
    then
      echo "Commit $commit ($c/$ccount): already processed."
      continue
    fi

    mkdir "$COMMIT_BASE"

    echo "Commit $commit ($c/$ccount): processing."

    metadata=$(git log -n 1 --pretty=raw $commit)
    parent=$(echo "$metadata" \
	| awk '/^parent / { $1=""; sub (" ", ""); print $0 }')
    committer=$(echo "$metadata" \
	| awk '/^committer / { NF=NF-2; $1=""; sub(" ", ""); print $0 }')
    date=$(echo "$metadata" | awk '/^committer / { print $(NF=NF-1); }')
    date=$(date -u -d "1970-01-01 $date sec")
    log=$(echo "$metadata" | awk '/^    / { print $0; exit }')
    loglong=$(echo "$metadata" | awk '/^    / { print $0; }')

    if test "$c" = "1"
    then
      # This commit is the current head of the branch.
      ln -sf "../commits/$commit" "$TARGET/branches/$branch"

      echo "<html><head><title>Branch: $branch</title></head>" \
          "<body>" \
          "<h2>Branch: $branch</h2>" \
          "<ul>" \
          > "$BRANCH_INDEX"

      echo "<li><a href=\"branches/$branch\">$branch</a> " \
        "$log $committer $date" >> "$INDEX"
    fi

    echo "<li><a href=\"../commits/$commit\">$log</a>: $committer $date" \
	>> "$BRANCH_INDEX"


    COMMIT_INDEX="$COMMIT_BASE/index.html"
    echo "<html><head><title>Commit: $commit</title></head>" \
        "<body>" \
	"<h2>Branch: $branch</h2>" \
        "<h3>Commit: $commit</h3>" \
	"<p>Committer: $committer" \
	"<br>Date: $date" \
	"<br>Parent: <a href=\"../$parent\">$parent</a>" \
	" (<a href=\"diff-to-parent.html\">diff to parent</a>)" \
	"<br>Log message:" \
	"<p><pre>$loglong</pre>" \
	"<p>" \
        "<ul>" \
        > "$COMMIT_INDEX"

    {
      echo "<html><head><title>diff $commit $parent</title></head>" \
        "<body>" \
	"<h2>Branch: $branch</h2>" \
        "<h3>Commit: <a href=\"index.html\">$commit</a></h3>" \
	"<p>Committer: $committer" \
	"<br>Date: $date" \
	"<br>Parent: <a href=\"../$parent\">$parent</a>" \
	"<br>Log message:" \
	"<p><pre>$loglong</pre>" \
	"<p>" \
        "<pre>"
      git diff $commit..$parent \
        | sed 's#<#\&lt;#g; s#>#\&gt;#g; ' \
	| awk '{ ++line; printf("%5d: %s\n", line, $0); }'
      echo "</pre></body></html>"
    } > "$COMMIT_BASE/diff-to-parent.html"

    FILES=$(mktemp)
    git ls-tree -r "$commit" > "$FILES"

    gawk 'function spaces(l) {
           for (space = 1; space <= l; space ++) { printf ("  "); }
         }
         function max(a, b) { if (a > b) { return a; } return b; }
         function min(a, b) { if (a < b) { return a; } return b; }
         BEGIN {
           current_components[1] = "";
           delete current_components[1];
         }
         {
           file=$4;
           split(file, components, "/")
           # Remove the file.  Keep the directories.
           file=components[length(components)]
           delete components[length(components)];

           # See if a path component changed.
           for (i = 1;
                i <= min(length(components), length(current_components));
                i ++)
           {
             if (current_components[i] != components[i])
             # It did.
             {
               last=length(current_components);
               for (j = last; j >= i; j --)
               {
                 spaces(j);
                 printf ("</ul> <!-- %s -->\n", current_components[j]);
                 delete current_components[j];
               }
             }
           }

           # See if there are new path components.
           for (; i <= length(components); i ++)
           {
               current_components[i] = components[i];
               spaces(i);
               printf("<li>%s\n", components[i]);
               spaces(i);
               printf("<ul>\n");
           }

           spaces(length(current_components))
           printf ("<li><a href=\"%s.raw.html\">%s</a>\n", $4, file);
         }' \
	< "$FILES" >> "$COMMIT_INDEX"

    while read line
    do
      file_base=$(echo "$line" | awk '{ print $4 }')
      file="$TARGET/commits/$commit/$file_base"
      sha=$(echo "$line" | awk '{ print $3 }')

      object_dir="$TARGET/objects/"$(echo "$sha" \
	  | sed 's#^\([a-f0-9]\{2\}\).*#\1#')
      object="$object_dir/$sha"

      echo "<li><a href=\"$file_base\">$file_base</a>" \
	>> "$COMMIT_INDEX"

      if test ! -e "$object"
      then
        # File does not yet exists in the object repository.
        # Create it.
	if test ! -d "$object_dir"
	then
	  mkdir "$object_dir"
	fi
	pretty_print "$branch" "$commit" "$TARGET/$commit" "$file_base" "$sha" \
	    > "$object"
      fi

      # Create a hard link to the file in the object repository.
      mkdir -p $(dirname "$file")
      ln "$object" "$file.raw.html"
    done <"$FILES"
    rm "$FILES"

    echo "</ul></body></html>" >> "$COMMIT_INDEX"
  done

  echo "</ul></body></html>" >> "$BRANCH_INDEX"
done

echo "</ul></body></html>" >> "$INDEX"
