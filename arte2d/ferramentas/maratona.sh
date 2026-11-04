#!/bin/bash
# maratona.sh [filtro]: gera os sprites de todos os modelos (menos propostas e tufo de grama), um Blender por vez.
# Retoma de onde parou: pula quem já tem o .json. Log em PlanetaFactory_2D/maratona.log
D=/mnt/d/Projetos/Jogos/PlanetaFactory_2D
J=/mnt/d/Projetos/Jogos/PlanetaFactory/jogo
B=~/.local/share/Steam/steamapps/common/Blender/blender
LOG=$D/maratona.log
python3 -c "
import json
d=json.load(open('$J/dados/modelos.json'))
for k,v in d.items():
    if v['categoria'].startswith('proposta') or k=='grama_tufo': continue
    print(k, v['categoria'].replace('/','_'))
" | grep -E "${1:-.}" > $D/lista.txt
total=$(wc -l < $D/lista.txt); i=0
while read nome cat; do
  i=$((i+1)); out=$D/sprites/$cat/$nome
  [ -f $out/$nome.json ] && continue
  mkdir -p $out; t0=$(date +%s)
  timeout 2400 $B -b --python $D/ferramentas/sprite_modelo.py -- $J $nome $out > $out/render.log 2>&1
  r=$(grep -E 'SPRITE_OK' $out/render.log | head -1)
  [ -z "$r" ] && r="FALHOU: $(grep -E 'Error|Traceback' $out/render.log | tail -2 | tr '\n' ' ')"
  echo "[$i/$total] $nome $(( $(date +%s)-t0 ))s $r" | tee -a $LOG
done < $D/lista.txt
echo "MARATONA FIM" | tee -a $LOG
