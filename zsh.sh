#!/usr/bin/env bash

set -ex

sudo apt update

# update
sudo apt update && sudo apt upgrade -y && sudo apt install -y \
    apt-utils \
    unzip \
    build-essential \
    nano \
    curl \
    sudo \
    unzip \
    wget \
    fontconfig \
    git \
    fzf \
    bash \
    curl \
    wget \
    python3 \
    watch \
    zsh \
    pip \
    nano \
    gcc \
    jq \
    vim \
    micro \
    bat \
    ncdu \
    zsh \
    xclip \
    fd-find 

TEMP_DIR=$HOME/temp
if [[ -d $TEMP_DIR ]]; then
    rm -rf $TEMP_DIR
fi
mkdir $TEMP_DIR
cd $TEMP_DIR


if [[ ! $(which dust) ]]; then
    DUST_VERSION=v1.0.0
    wget https://github.com/bootandy/dust/releases/download/${DUST_VERSION}/dust-${DUST_VERSION}-x86_64-unknown-linux-gnu.tar.gz
    tar -xf dust-${DUST_VERSION}-x86_64-unknown-linux-gnu.tar.gz
    sudo mv ./dust-${DUST_VERSION}-x86_64-unknown-linux-gnu/dust /usr/bin
    sudo chmod +x /usr/bin/dust
fi

if [[ ! $(which exa) ]]; then
    EXA_VERSION=v0.10.1
    wget https://github.com/ogham/exa/releases/download/${EXA_VERSION}/exa-linux-x86_64-musl-${EXA_VERSION}.zip
    unzip exa-linux-x86_64-musl-${EXA_VERSION}.zip
    sudo mv ./bin/exa /usr/bin
fi

if [[ ! $(which tokei) ]]; then
    TOKEI_VERSION=v12.1.2
    wget https://github.com/XAMPPRocky/tokei/releases/download/${TOKEI_VERSION}/tokei-x86_64-unknown-linux-gnu.tar.gz
    tar -xf tokei-x86_64-unknown-linux-gnu.tar.gz
    sudo mv ./tokei /usr/bin
    sudo chmod +x /usr/bin/tokei
fi

if [[ ! $(which starship) ]]; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

if [[ ! $(which sd) ]]; then
    wget https://github.com/chmln/sd/releases/download/v0.7.6/sd-v0.7.6-x86_64-unknown-linux-gnu -O /usr/bin/sd &&
        sudo chmod +x /usr/bin/sd
fi

if [[ ! $(which k9s) ]]; then
    curl -sS https://webi.sh/k9s | sh
fi

if [[ ! $(which nvm) ]]; then
    # install node version manager
    curl -L https://raw.githubusercontent.com/tj/n/master/bin/n -o n
    sudo chmod +x ./n
    sudo mv ./n /bin
    sudo n lts
fi

if [[ ! -d ~/.fonts ]]; then
    wget https://github.com/ryanoasis/nerd-fonts/releases/download/v2.2.2/CascadiaCode.zip
    unzip CascadiaCode.zip -d CascadiaCode
    mkdir ~/.fonts
    mv ./CascadiaCode/* ~/.fonts
    fc-cache -fv
    # delete temp file
fi

cd ..
rm -rf $TEMP_DIR

# zsh
if [[ ! -d ~/.oh-my-zsh ]]; then
    export RUNZSH=no
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/plugins/zsh-autosuggestions
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    git clone https://github.com/Aloxaf/fzf-tab ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all --no-fish --no-bash
    rm -rf ~/fzf
fi

# replace .zshrc
cat <<EOT >~/.zshrc
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"

plugins=(colorize fzf zsh-autosuggestions zsh-navigation-tools command-not-found cp dotenv zsh-syntax-highlighting)

source \$ZSH/oh-my-zsh.sh
ENABLE_CORRECTION="true"
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

alias p="pnpm"

u_tag_move() {
    [ ! \$1 ] && echo "please provide a tag name" && exit 1
    git tag -d \$1
    git push --delete origin \$1
    git tag \$1
    git push origin \$1
}
u_tag_delete() {
    [ ! \$1 ] && echo "please provide a tag name" && exit 1
    git tag -d \$1
    git push --delete origin \$1
}

u_tag_create() {
    [ ! \$1 ] && echo "please provide a tag name" && exit 1
    git tag \$1
    git push origin \$1
}

his() {
    history | grep \$1
}

gcp() {
    if [[ \$1 ]]; then
        git add "\$@"
    else
        git add .
    fi
    git commit -am "\$(git status --porcelain)"
    local STATUS=\$(git push 2>&1)
    echo \$STATUS
    if [[ \$(echo \$STATUS | grep "upstream") ]]; then
        echo "Creating branch \n"
        local COMMAND=\$(echo \$STATUS | sed '4p;d')
        bash -c \$COMMAND
    fi
}

gc() {
    if [[ \$1 ]]; then
        git add "\$@"
    else
        git add .
    fi
    git commit -am "\$(git status --porcelain)"
}

alias ls="exa -h"

export TERM='xterm-256color'
export EDITOR="nano"

export STARSHIP_CONFIG=~/.config/starship.toml

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export PATH=\$PATH:/snap/bin:/home/alpap/repos/aws-live/bin:/home/alpap/.local/bin/:/bin:/usr/bin:/usr/local/bin/
eval "source <(/usr/local/bin/starship init zsh --print-full-init)"
EOT

[[ ! -d ~/repos ]] && mkdir ~/repos

[[ ! -d ~/.config ]] && mkdir ~/.config

cat <<EOT >~/.config/starship.toml
[container]
disabled = true

[sudo]
disabled = false
symbol = '💀 '
EOT

