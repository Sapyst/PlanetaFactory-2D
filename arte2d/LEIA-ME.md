# PlanetaFactory 2D: sprites

Esta pasta guarda os sprites 2D de todos os modelos do jogo. Ela fica fora do repositório do jogo 3D e não muda nada nele.
Os modelos de origem são os mesmos `.glb` do jogo, lidos de `../PlanetaFactory/jogo/assets/modelos`. São 253 modelos.
Ficaram de fora as 4 propostas antigas e o tufo de grama.

## Estilo
- **Visual:** pixel art realista e escura. Só o modelo escurece, porque a mudança está no material: cor dessaturada, luz em degraus e um brilho estreito nas quinas de metal. A natureza não tem esse brilho.
- **Câmera:** ortográfica, de frente e meio de cima, a 35°. A escala é a mesma em tudo: 1 pixel equivale a 2,875 cm, ou seja, 4,6 m em 160 px.
- **Render:** a cor é renderizada em 4x e reduzida pela média. A silhueta tem contorno escuro de 1 px.
- **Peças finas:** cabos, tirantes e grades com menos de 1 px de largura viram uma linha escura de 1 px, sem contorno.
- **Sombra:** fica numa folha à parte (`*_sombra.png`), em preto com 50% de opacidade. Ela vai embaixo do sprite. O sol vem da esquerda e de trás da câmera.

## Arquivos de cada modelo (`sprites/<categoria>/<nome>/`)
- `<nome>.png` e `<nome>_sombra.png`: folhas com fundo transparente. As linhas são as rotações ou direções, e as colunas são os quadros.
- **Braços:** têm `<nome>_atras.png`, `_esquerda.png` e `_direita.png`, uma folha por origem do modo Radial. O destino é sempre a frente.
- `<nome>.json` traz estes campos:
  - `quadro`: largura e altura de cada quadro, em pixels.
  - `ancora`: o pixel do centro do tile no chão, para alinhar com a grade.
  - `fps`: sempre 12.
  - `quadros` e `linhas`: quantos quadros e quantas linhas a folha tem.
  - `tipo_linha`: `rotacao` (0, 90, 180 e 270°, girando no sentido anti-horário visto de cima) ou `direcao` (360° divididos por `linhas`).
  - `variantes` e `animacao`.

## Linhas e animação por tipo
| Tipo | Linhas | Quadros |
|---|---|---|
| Construção | 4 rotações | 1 parada; 48 com a animação "trabalho" do jogo (laço de 4 s) |
| Esteira | 4 rotações | 16, com a lona andando; rápida 2×, expressa 3× e quântica 4× |
| Braço | 4 rotações × 3 origens | 28, com a mesma cinemática do `animador.gd` e item na garra só na ida |
| Torre de defesa | 16 direções do canhão | 1 |
| Trem e vagão | 16 direções | 1 |
| Drone | 8 direções | 8, com as hélices girando |
| Aranha montada | 8 direções | 1 |
| Mapa e itens | 1 | 1 |

## Ferramentas (`ferramentas/`)
- `sprite_modelo.py`: um modelo. Rode com `blender -b --python sprite_modelo.py -- <jogo> <nome> <saida>`.
- `maratona.sh [filtro]`: todos os modelos, um Blender por vez. Retoma pulando quem já tem `.json`. O log fica em `maratona.log`.
- `previa.py`: GIF de um modelo. `pranchas.py`: prancha `.png` e vídeo `.mp4` por categoria, em `previas/`.
- `indice.json` lista todos os modelos com os dados principais.

## Luz dos objetos (à noite)
- **Origem:** `ferramentas/luzes2d.py` leva a luz das estruturas do jogo 3D (`jogo/dados/luzes.json`: 51 máquinas e 3 postes) para o campo `luz` do `.json` de cada sprite.
- **Campos:**
  - `tipo`: fogo, cristal, choque, lâmpada ou poste.
  - `cor` e `forca`.
  - `raio_px`.
  - `pos_px`: onde fica a fonte, um ponto por linha da folha.
  - `chao_px`: a base da fonte no chão, um ponto por linha. A poça de luz é uma elipse em volta dela.
  - `chamas`: posição, tamanho e `cresce` de cada labareda.
  - `arcos`: as pontas de cada arco elétrico.
- **Quando acende:** só à noite e com a máquina ativa, como no 3D. A cor do poste vem da rede de energia.
- **Labaredas:** ficam em `efeitos/labareda_<altura>px[_cresce].png`. São 12 quadros em pixel art, com âncora no centro da base.
- **Como desenhar:** o motor 2D multiplica a cor pela luz. A luz é o ambiente da noite mais a poça no chão e o brilho na peça perto da fonte. Os degraus da luz levam pontilhado 4×4 para não formar anéis.
- **Prévia:** `ferramentas/noite2d.py` gera o "dia | noite" (exemplo em `previas/noite.mp4`).

## Limites conhecidos
- **Aranha:** a caminhada é feita por código no jogo, então o sprite dela fica parado. As pernas soltas, fêmur e tíbia, também têm sprite.
- **Metralhadora:** o tambor não gira.
- **Turbina:** a nacele aponta sempre para o mesmo lado e só a hélice gira.
- **Lona da esteira:** anda mais devagar que no jogo, para caber num laço curto. No 2D, o ideal é o motor do jogo rolar a lona.
- **Plataforma e ponte de água:** as pernas aparecem, porque no 3D elas ficam dentro da água.
- **Árvores:** a conversão do ambiente (commit 7a9643d do jogo) perdeu o material de folha, e no `.glb` a copa ficou cinza. No sprite, a copa volta à cor de verão de cada espécie, tirada dos modelos antigos (commit 5951dc9).
