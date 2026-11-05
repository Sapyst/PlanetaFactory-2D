"""Sons do jogo sintetizados por código (sem amostras de terceiros): efeitos e ambientes (sem música).
Saída: assets/sons/*.wav (mono 16 bits, 44,1 kHz).
Rodar: python3 ferramentas/gerar_sons.py [nome ...]   (sem nome = todos; precisa de numpy e scipy)
       SONS_SAIDA=<pasta> muda a pasta de saída (para comparar antes de trocar).

Cada som é feito em camadas, como um som gravado: o estalo do começo (transiente), o corpo e a cauda; o metal
é batido (parciais inarmônicas, cada uma com a própria queda); o ruído passa por filtros de verdade (passa-banda
ressonante, passa-baixa de 4ª ordem) em vez de ruído branco cru, que soa fino e digital. No fim, tudo passa pela
mesma finalização: reverberação curta de lugar aberto (dosada por som), corte de grave inaudível, fades nas
pontas (sem estalo), laço emendado com crossfade (chuva, vento, fogo, máquinas) e volume calibrado pelo pico de
curto prazo (janelas de 50 ms), com limitador suave."""
import os, sys
import numpy as np
from scipy import signal
from scipy.io import wavfile

TAXA = 44100
AQUI = os.path.dirname(os.path.abspath(__file__))
SAIDA = os.environ.get('SONS_SAIDA') or os.path.join(AQUI, '..', 'assets', 'sons')


# ------------------------------------------------------------------ blocos
def tempo(d):
    return np.arange(int(d * TAXA)) / TAXA


def ruido(n, rng):
    return rng.uniform(-1.0, 1.0, n)


def rosa(n, rng):
    """Ruído rosa (−3 dB por oitava): soa mais natural que o branco."""
    x = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / TAXA)
    f[0] = f[1]
    y = np.fft.irfft(x / np.sqrt(f), n)
    return y / (np.abs(y).max() + 1e-12)


def _sos(x, sos):
    return signal.sosfilt(sos, x)


def pb(x, fc, ordem=4):
    """Passa-baixa."""
    return _sos(x, signal.butter(ordem, min(fc, TAXA * 0.45), 'low', fs=TAXA, output='sos'))


def pa(x, fc, ordem=2):
    """Passa-alta."""
    return _sos(x, signal.butter(ordem, fc, 'high', fs=TAXA, output='sos'))


def banda(x, f1, f2, ordem=2):
    """Passa-banda entre f1 e f2."""
    return _sos(x, signal.butter(ordem, [f1, min(f2, TAXA * 0.45)], 'band', fs=TAXA, output='sos'))


def ressoa(x, f, q):
    """Ressonância estreita (corpo oco, tubo, chapa)."""
    b, a = signal.iirpeak(f, q, fs=TAXA)
    return signal.lfilter(b, a, x)


def pb_varia(x, cortes):
    """Passa-baixa de 1 polo com corte que muda amostra a amostra (filtro que abre e fecha)."""
    al = 1.0 - np.exp(-2 * np.pi * np.asarray(cortes) / TAXA)
    y = np.empty_like(x)
    v = 0.0
    for i in range(len(x)):
        v += al[i] * (x[i] - v)
        y[i] = v
    return y


def env(n, ataque=0.002, queda=0.1, sustenta=0.0):
    """Ataque em cosseno (sem estalo), sustentação opcional e queda exponencial."""
    t = np.arange(n) / TAXA
    a = np.clip(t / max(ataque, 1e-5), 0, 1)
    a = 0.5 - 0.5 * np.cos(np.pi * a)
    d = np.where(t < ataque + sustenta, 1.0, np.exp(-(t - ataque - sustenta) / queda))
    return a * d


def osc(freqs, forma='sen', fase=0.0):
    """Oscilador com frequência variável (Hz por amostra)."""
    ph = 2 * np.pi * np.cumsum(np.asarray(freqs, dtype=float)) / TAXA + fase
    if forma == 'sen':
        return np.sin(ph)
    if forma == 'serra':
        return signal.sawtooth(ph)
    if forma == 'quad':
        return signal.square(ph)
    return signal.sawtooth(ph, 0.5)


def varre(f0, f1, d, curva=1.0):
    """Frequência que vai de f0 a f1 em d segundos (curva > 1 cai depressa no começo)."""
    t = np.linspace(0, 1, int(d * TAXA))
    return f0 + (f1 - f0) * (1 - (1 - t) ** curva)


def metal(parciais, d, rng=None, brilho=1.0):
    """Metal batido: [(freq, queda_s, amplitude)], cada parcial com fase e leve desafinação próprias."""
    t = tempo(d)
    out = np.zeros_like(t)
    for f, q, a in parciais:
        ph = rng.uniform(0, 2 * np.pi) if rng is not None else 0.0
        out += a * np.sin(2 * np.pi * f * brilho * t * (1 + 0.0015 * np.sin(2 * np.pi * 3.1 * t)) + ph) * np.exp(-t / q)
    return out


PLACA = [1.0, 1.59, 2.14, 2.30, 2.65, 2.92, 3.50, 4.15, 4.70, 5.40, 6.20]   # modos de uma chapa (inarmônicos)


def modal(rng, base, d, q=12.0, modos=8, excita=0.002, cor=(200, 8000), espalha=0.06):
    """Corpo que ressoa batido: um pulso de ruído excita um banco de filtros ressonantes (modos de chapa).
    Q baixo = "clanc"/"toc" abafado; Q alto = sino. Soa como coisa batida, não como senoide pura."""
    n = int(d * TAXA)
    ex = banda(ruido(n, rng), *cor) * env(n, 0.0007, excita)
    out = np.zeros(n)
    for r in PLACA[:modos]:
        f = min(base * r * (1 + rng.uniform(-espalha, espalha)), TAXA * 0.42)
        out += ressoa(ex, f, q * rng.uniform(0.7, 1.3)) * rng.uniform(0.5, 1.0) / r ** 0.3
    return out


def graos(rng, d, n, f1, f2, q=4.0, dur=(0.0005, 0.002), forma=None):
    """Granulado: n estalinhos curtos, cada um filtrado numa frequência ao acaso entre f1 e f2, espalhados em d s.
    É o som de terra esmagando, cascalho e chapa amassando (forma(u) dá o envelope, u de 0 a 1)."""
    N = int(d * TAXA)
    out = np.zeros(N + int(0.02 * TAXA))
    for t0 in np.sort(rng.uniform(0, d, n)):
        L = int(rng.uniform(*dur) * TAXA) + 2
        g = np.concatenate([ruido(L, rng) * np.hanning(L), np.zeros(int(0.012 * TAXA))])
        g = ressoa(g, np.exp(rng.uniform(np.log(f1), np.log(f2))), q)
        i = int(t0 * TAXA)
        out[i:i + len(g)] += g[:len(out) - i] * rng.uniform(0.3, 1.0) * (forma(t0 / d) if forma else 1.0)
    return out


def surdo(rng, d, fc=220, queda=0.03):
    """Peso caindo: ruído grave curto (soa como massa, não como bumbo eletrônico)."""
    n = int(d * TAXA)
    return pb(rosa(n, rng), fc) * env(n, 0.001, queda)


def chiado_hidraulico(rng, d, f1=5000, f2=700):
    """Ar/óleo escapando de um pistão: ruído que fecha de f1 para f2."""
    n = int(d * TAXA)
    return pb_varia(banda(rosa(n, rng), 600, 9000), np.linspace(f1, f2, n)) * env(n, 0.01, d * 0.35)


def estalo(d, rng, f1=1500, f2=7000, queda=0.004):
    """Transiente curto: ruído em banda com queda rápida."""
    n = int(d * TAXA)
    return banda(ruido(n, rng), f1, f2) * env(n, 0.0004, queda)


def baque(f0, f1, d, queda, curva=3.0):
    """Baque grave: senoide que despenca de f0 a f1."""
    n = int(d * TAXA)
    return osc(varre(f0, f1, d, curva)) * env(n, 0.001, queda)


def estalos(d, taxa, rng, f1=1500, f2=6000, queda=0.003, amp=(0.3, 1.0)):
    """Crepitar: estalos curtos espalhados ao acaso (fogo, faísca, cascalho)."""
    n = int(d * TAXA)
    out = np.zeros(n)
    k = int(0.03 * TAXA)
    for _ in range(int(taxa * d)):
        i = rng.integers(0, max(1, n - k))
        out[i:i + k] += estalo(0.03, rng, f1, f2, queda)[:n - i] * rng.uniform(*amp)
    return out


def junta(*partes):
    """Soma camadas: (sinal, ganho, atraso_s)."""
    n = max(int(at * TAXA) + len(x) for x, g, at in partes)
    out = np.zeros(n)
    for x, g, at in partes:
        i = int(at * TAXA)
        out[i:i + len(x)] += g * x
    return out


def satura(x, k=2.0):
    """Saturação suave (corpo e peso sem distorcer feio)."""
    return np.tanh(k * x) / np.tanh(k)


_IR = {}


def reverb(x, tempo_s=0.6, umido=0.2, brilho=5000, pre=0.012, seed=1):
    """Reverberação de lugar aberto: reflexões iniciais esparsas + cauda de ruído que escurece com o tempo."""
    chave = (tempo_s, brilho, pre, seed)
    if chave not in _IR:
        rng = np.random.default_rng(seed)
        n = int((tempo_s + pre) * TAXA)
        t = np.arange(n) / TAXA
        cauda = rng.standard_normal(n) * np.exp(-6.9 * t / tempo_s)
        cauda = 0.5 * pb(cauda, brilho, 2) + 0.5 * pb(cauda, brilho * 0.25, 2)   # agudo morre antes
        cauda[:int(pre * TAXA)] = 0
        for _ in range(9):                                                       # ecos do chão e de perto
            i = int(rng.uniform(pre * 0.5, pre * 4) * TAXA)
            cauda[i] += rng.uniform(0.3, 0.8) * rng.choice([-1, 1])
        _IR[chave] = cauda / np.sqrt(np.sum(cauda ** 2))
    molhado = signal.fftconvolve(x, _IR[chave])
    seco = np.concatenate([x, np.zeros(len(molhado) - len(x))])
    return seco + umido * molhado


def laco(x, cruza=0.35):
    """Emenda o fim no começo com crossfade de potência igual: toca em laço sem estalo."""
    k = int(cruza * TAXA)
    y = x[:-k].copy()
    w = np.linspace(0, np.pi / 2, k)
    y[:k] = x[:k] * np.sin(w) + x[-k:] * np.cos(w)
    return y


# ------------------------------------------------------------------ finalização e gravação
def finalizar(x, alvo_db, laco_s=0.0, fade_in=0.0015, fade_out=0.02):
    x = np.asarray(x, dtype=float)
    x = pa(x, 28, 2)                                     # sem grave inaudível (gasta volume, embola o mix)
    if laco_s > 0:
        x = laco(x, laco_s)
    else:
        ab = np.abs(x)                                   # corta o silêncio do fim (abaixo de −60 dB do pico)
        fim = len(x) - np.argmax(ab[::-1] > ab.max() * 1e-3)
        x = x[:max(fim, int(0.02 * TAXA))]
        ni, no = int(fade_in * TAXA), int(fade_out * TAXA)
        if ni > 1:
            x[:ni] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, ni))
        if no > 1:
            x[-no:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, no))
    w = int(0.05 * TAXA)
    st = max(np.sqrt(np.mean(x[i:i + w] ** 2)) for i in range(0, max(1, len(x) - w + 1), w // 2))
    x = x * min(10 ** (alvo_db / 20) / (st + 1e-12), 0.7 / (np.abs(x).max() + 1e-12))   # pico até −3 dB: sem esmagar o ataque
    lim = 0.8                                            # limitador suave: pico nunca passa de ~0,95
    acima = np.abs(x) > lim
    x[acima] = np.sign(x[acima]) * (lim + (1 - lim) * np.tanh((np.abs(x[acima]) - lim) / (1 - lim)) * 0.75)
    return x


def gravar(nome, x):
    os.makedirs(SAIDA, exist_ok=True)
    wavfile.write(os.path.join(SAIDA, nome + '.wav'), TAXA, (np.clip(x, -1, 1) * 32767).astype(np.int16))


# ==============================================================================
# INTERFACE E AÇÕES GERAIS
# ==============================================================================
def clique(rng):
    """Tecla mecânica: dois toques quase juntos (descer e assentar) com ressonância pequena de plástico duro."""
    a = ressoa(estalo(0.03, rng, 2000, 9000, 0.0015), 2300, 6) * 0.6 + estalo(0.03, rng, 2500, 8000, 0.001)
    b = ressoa(estalo(0.03, rng, 1500, 6000, 0.002), 1700, 5) * 0.5
    return junta((a, 1.0, 0), (b, 0.55, 0.011))


def construir(rng):
    """Peça assentando: baque grave no chão, clangor de chapa e a trava fechando logo depois."""
    corpo = baque(170, 85, 0.35, 0.06)
    chapa = metal([(310, 0.09, 1.0), (747, 0.06, 0.6), (1270, 0.045, 0.45), (2130, 0.03, 0.3), (3390, 0.02, 0.2)], 0.4, rng)
    poeira = pb(rosa(int(0.25 * TAXA), rng), 900) * env(int(0.25 * TAXA), 0.003, 0.05)
    trava = ressoa(estalo(0.05, rng, 1500, 7000, 0.002), 2600, 8)
    x = junta((corpo, 0.45, 0), (chapa, 0.6, 0.002), (poeira, 0.5, 0), (estalo(0.02, rng, 800, 5000, 0.003), 0.7, 0),
              (trava, 0.5, 0.075), (estalo(0.02, rng, 2000, 8000, 0.0015), 0.35, 0.078))
    return reverb(satura(x, 1.5), 0.45, 0.16)


def remover(rng):
    """Trava abrindo e ar escapando: clique, sopro que desce de tom e a peça soltando com um toque oco."""
    n = int(0.3 * TAXA)
    sopro = pb_varia(banda(rosa(n, rng), 400, 9000), np.linspace(6000, 900, n)) * env(n, 0.01, 0.09)
    oco = ressoa(estalo(0.08, rng, 300, 2000, 0.01), 420, 10)
    x = junta((ressoa(estalo(0.03, rng, 1500, 7000, 0.0015), 2400, 7), 0.8, 0), (sopro, 1.0, 0.012), (oco, 0.6, 0.12),
              (metal([(520, 0.05, 1), (1310, 0.03, 0.5)], 0.2, rng), 0.25, 0.12))
    return reverb(x, 0.4, 0.14)


def alerta(rng):
    """Sirene de fábrica: buzina de dois tons com vibrato, passando por uma corneta (formantes), e o eco do lugar."""
    partes = []
    for k, nota in enumerate((660, 495, 660, 495)):
        d = 0.24
        n = int(d * TAXA)
        f = nota * (1 + 0.006 * np.sin(2 * np.pi * 6.5 * tempo(d)))
        s = osc(f, 'serra') * 0.6 + osc(f * 1.005, 'quad') * 0.4
        s = ressoa(s, 1100, 1.4) + 0.6 * ressoa(s, 2400, 2.5) + 0.3 * pb(s, 900)
        partes.append((pb(s, 4500) * env(n, 0.012, 0.5, d - 0.06), 1.0, k * 0.26))
    return reverb(satura(junta(*partes), 1.3), 0.9, 0.3)


def pesquisa(rng):
    """Sinos de tecnologia: arpejo que sobe com timbre de sino (parciais inarmônicas) e brilho no fim."""
    partes = []
    for k, nota in enumerate((523.25, 659.25, 783.99, 1046.5, 1318.5)):
        sino = metal([(nota, 0.9, 1.0), (nota * 2.0, 0.45, 0.35), (nota * 2.76, 0.25, 0.22), (nota * 5.4, 0.12, 0.1),
                      (nota * 0.5, 1.2, 0.18)], 1.4, rng)
        sino *= env(len(sino), 0.002, 10.0)
        partes.append((sino, 0.9 - 0.08 * k, k * 0.09))
    brilho = pa(rosa(int(0.8 * TAXA), rng), 6000) * env(int(0.8 * TAXA), 0.15, 0.25)
    return reverb(junta(*partes, (brilho, 0.06, 0.35)), 1.6, 0.35, 7000)


def derrota(rng):
    """Metais graves descendo, abafados e cansados: a fábrica apagando."""
    partes = []
    for k, nota in enumerate((196, 174.6, 155.6, 116.5, 87.3)):
        d = 0.55 if k < 4 else 1.4
        n = int(d * TAXA)
        f = nota * (1 + 0.004 * np.sin(2 * np.pi * 4.8 * tempo(d)))
        s = osc(f, 'serra') + 0.5 * osc(f * 0.5, 'serra')
        s = pb_varia(s, 300 + 1600 * env(n, 0.05, 0.25))
        partes.append((s * env(n, 0.04, 0.5 if k < 4 else 0.9, 0.15), 1.0, k * 0.36))
    return reverb(satura(junta(*partes), 1.4), 1.8, 0.35, 3000)


# ==============================================================================
# ARMAS
# ==============================================================================
def _disparo(rng, estalo_g=1.0, corpo_f=(500, 2200), corpo_q=0.035, grave=(210, 95), grave_q=0.035, cauda=0.35,
             umido=0.22, mec=True):
    """Tiro: estalo supersônico + explosão do cano (ruído em banda) + soco médio-grave + mecanismo + eco do lugar.
    O peso fica entre 150 Hz e 6 kHz: grave fundo demais some no alto-falante do celular."""
    n = int(0.25 * TAXA)
    corpo = banda(ruido(n, rng), *corpo_f) * env(n, 0.0006, corpo_q)
    soco = ressoa(rosa(n, rng), 260, 2.5) * env(n, 0.0008, corpo_q * 0.8)
    x = junta((estalo(0.02, rng, 2500, 12000, 0.0025), estalo_g * 1.6, 0), (corpo, 2.2, 0.0008), (soco, 0.9, 0),
              (baque(grave[0], grave[1], 0.2, grave_q), 0.3, 0))
    if mec:
        x = junta((x, 1.0, 0), (metal([(1850, 0.012, 1), (3100, 0.008, 0.6)], 0.05, rng), 0.12, 0.028))
    return reverb(satura(x, 2.2), cauda, umido, 4500)


def tiro_metralhadora(rng):
    """Metralhadora: tiro seco e curto, com o ferrolho batendo."""
    return _disparo(rng)


def tiro(rng):
    """Tiro genérico (lançador de semente)."""
    return _disparo(rng, 0.8, (400, 1800), 0.045, (190, 85), 0.045, 0.45, 0.25)


def tiro_perfurante(rng):
    """Bala perfurante: estalo mais duro, cano que soa metálico e eco mais longo."""
    x = _disparo(rng, 1.3, (700, 3000), 0.03, (230, 100), 0.03, 0.5, 0.25)
    anel = metal([(2470, 0.06, 1), (3710, 0.04, 0.6), (5220, 0.025, 0.3)], 0.15, rng)
    return junta((x, 1.0, 0), (anel, 0.08, 0.004))


def tiro_carregada(rng):
    """Bala carregada: o tiro com um zumbido elétrico que estala junto."""
    x = _disparo(rng, 1.0, (500, 2200), 0.035, (210, 95), 0.035, 0.4, 0.2)
    n = int(0.22 * TAXA)
    zum = osc(np.full(n, 120.0), 'serra') * (0.5 + 0.5 * osc(np.full(n, 37.0), 'quad'))
    zum = banda(zum, 300, 5000) * env(n, 0.002, 0.07)
    return junta((x, 1.0, 0), (zum, 0.35, 0.005), (estalos(0.2, 90, rng, 3000, 9000, 0.0015), 0.3, 0.005))


def tiro_energia(rng):
    """Torre de energia: descarga que desce de tom (FM) sobre um estalo de capacitor e um zumbido curto."""
    d = 0.3
    n = int(d * TAXA)
    f = varre(1900, 220, d, 2.5)
    mod = osc(f * 1.5) * 3.0 * env(n, 0.001, 0.08)
    raio = np.sin(2 * np.pi * np.cumsum(f) / TAXA + mod) * env(n, 0.001, 0.07)
    sub = baque(160, 60, 0.25, 0.05)
    chiado = banda(ruido(n, rng), 2000, 9000) * env(n, 0.0005, 0.02)
    return reverb(satura(junta((raio, 0.8, 0), (sub, 0.7, 0), (chiado, 0.4, 0)), 1.6), 0.5, 0.2)


def tiro_foguete(rng):
    """Lança-foguetes: ignição que estoura e o motor rasgando o ar, sumindo para longe."""
    d = 0.9
    n = int(d * TAXA)
    jato = pb_varia(pa(rosa(n, rng), 160), np.concatenate([np.linspace(800, 5000, n // 5), np.linspace(5000, 900, n - n // 5)]))
    jato = jato * env(n, 0.02, 0.22, 0.08)
    x = junta((estalo(0.04, rng, 600, 6000, 0.006), 1.0, 0), (baque(150, 70, 0.3, 0.06), 0.4, 0), (jato, 1.6, 0.01),
              (estalos(0.4, 40, rng, 1000, 5000, 0.004, (0.1, 0.4)), 0.5, 0.03))
    return reverb(satura(x, 1.6), 0.8, 0.25)


def tiro_enxame(rng):
    """Enxame: três foguetinhos saindo em sequência rápida, cada um com o seu chiado."""
    partes = []
    for k in range(3):
        d = 0.35
        n = int(d * TAXA)
        jato = pb_varia(pa(rosa(n, rng), 200), np.linspace(6000, 1200, n)) * env(n, 0.005, 0.08)
        partes += [(estalo(0.03, rng, 800, 7000, 0.003), 0.8, k * 0.055), (jato, 0.8, k * 0.055 + 0.004),
                   (baque(190, 95, 0.12, 0.025), 0.25, k * 0.055)]
    return reverb(satura(junta(*partes), 1.5), 0.6, 0.22)


def tiro_artilharia(rng):
    """Artilharia: estrondo grave do canhão, a onda de choque e o eco rolando longe."""
    d = 1.4
    n = int(d * TAXA)
    rolo = banda(rosa(n, rng), 140, 1300) * env(n, 0.005, 0.35)
    m = int(0.4 * TAXA)
    x = junta((estalo(0.04, rng, 800, 9000, 0.005), 1.8, 0), (baque(120, 45, 0.8, 0.2, 2.0), 0.25, 0),
              (ressoa(rosa(m, rng), 170, 2) * env(m, 0.001, 0.08), 1.6, 0),
              (banda(ruido(m, rng), 300, 2500) * env(m, 0.001, 0.05), 2.0, 0.001), (rolo, 1.4, 0.02))
    return reverb(satura(x, 2.0), 1.6, 0.35, 2500)


def tiro_drone(rng):
    """Drone de defesa: tiro de calibre pequeno (estalo seco, cano curto), o ferrolho miúdo e o eco curto do campo."""
    n = int(0.12 * TAXA)
    corpo = banda(ruido(n, rng), 500, 3000) * env(n, 0.0005, 0.022)
    x = junta((estalo(0.02, rng, 3000, 12000, 0.0018), 1.0, 0), (corpo, 1.8, 0.0005),
              (ressoa(rosa(n, rng), 300, 2.5) * env(n, 0.0006, 0.02), 1.3, 0),
              (metal([(2600, 0.008, 1), (4100, 0.006, 0.5)], 0.04, rng), 0.1, 0.02))
    return reverb(satura(x, 2.0), 0.3, 0.16, 5000)


def cuspe_acido(rng):
    """Larva cuspindo: pigarro molhado na garganta (gorgolejo), o "ptu" da gosma saindo e gotas espirrando."""
    n = int(0.22 * TAXA)
    t = tempo(0.22)
    gorgolejo = banda(rosa(n, rng), 250, 1600) * (0.5 + 0.5 * np.sin(2 * np.pi * 38 * t + 2 * np.sin(2 * np.pi * 7 * t))) ** 2
    gorgolejo = ressoa(gorgolejo, 520, 2.5) * env(n, 0.03, 0.06, 0.08)
    m = int(0.14 * TAXA)
    ptu = banda(ruido(m, rng), 700, 4500) * env(m, 0.002, 0.03) + ressoa(rosa(m, rng), 180, 3) * env(m, 0.002, 0.03) * 0.8
    gotas = graos(rng, 0.25, 40, 900, 4500, 6.0, (0.0004, 0.0015), lambda u: (1 - u) ** 1.5)
    return reverb(junta((gorgolejo, 0.9, 0), (ptu, 1.2, 0.17), (gotas, 0.5, 0.2)), 0.35, 0.12)


def acido_respingo(rng):
    """Gosma ácida batendo: "splat" líquido, gotas caindo em volta e o chiado do ácido corroendo, sumindo."""
    m = int(0.1 * TAXA)
    splat = banda(rosa(m, rng), 300, 3500) * env(m, 0.001, 0.025) + ressoa(rosa(m, rng), 220, 2.5) * env(m, 0.001, 0.03)
    gotas = graos(rng, 0.35, 70, 800, 5000, 7.0, (0.0004, 0.0016), lambda u: (1 - u) ** 2)
    n = int(1.4 * TAXA)
    chiado = pa(banda(ruido(n, rng), 2500, 11000), 2000) * env(n, 0.04, 0.45)
    chiado *= 0.8 + 0.2 * graos(rng, 1.4, 300, 3000, 9000, 2.0)[:n] * 3
    return reverb(junta((splat, 1.3, 0), (gotas, 0.6, 0.01), (chiado, 0.11, 0.03)), 0.3, 0.1)


# ==============================================================================
# IMPACTOS E EXPLOSÕES
# ==============================================================================
def impacto_aranha_a(rng):
    """Bala na carapaça (aço grosso): estalo, um "tunc" metálico abafado e lasquinhas."""
    return reverb(satura(junta((estalo(0.02, rng, 2000, 9000, 0.002), 0.3, 0), (modal(rng, 620, 0.12, 7, 8, 0.0012, (300, 6000)), 1.0, 0.0005),
                        (surdo(rng, 0.06, 400, 0.012), 0.35, 0), (estalos(0.06, 150, rng, 2500, 7000, 0.0012, (0.05, 0.3)), 0.12, 0.004)), 2.5),
                  0.35, 0.14)


def impacto_aranha_b(rng):
    """Bala na carapaça (casca de inseto): estalo seco que racha, sem anel."""
    return reverb(satura(junta((estalo(0.02, rng, 1500, 8000, 0.0018), 0.3, 0), (modal(rng, 700, 0.06, 6, 6, 0.0008, (300, 6000)), 1.0, 0),
                        (modal(rng, 330, 0.06, 5, 5, 0.001, (150, 3500)), 0.8, 0),
                        (estalos(0.05, 260, rng, 1200, 6000, 0.001, (0.1, 0.6)), 0.2, 0.002)), 2.5), 0.3, 0.12)


def impacto_chao(rng):
    """Tiro no chão: terra batida e cascalho caindo."""
    n = int(0.3 * TAXA)
    terra = banda(rosa(n, rng), 200, 2200) * env(n, 0.001, 0.05)
    return reverb(junta((baque(190, 85, 0.15, 0.035), 0.4, 0), (terra, 0.9, 0), (estalo(0.02, rng, 900, 4000, 0.003), 0.6, 0),
                        (estalos(0.25, 60, rng, 1200, 4500, 0.003, (0.05, 0.3)), 0.4, 0.03)), 0.4, 0.15)


def impacto_estrutura_a(rng):
    """Mordida na construção (mandíbula hidráulica): as presas batem na chapa (clanc grosso), o aço amassa,
    os dentes raspam e o pistão alivia."""
    golpe = modal(rng, 260, 0.4, 6, 10, 0.004, (150, 6000))
    n = int(0.22 * TAXA)
    raspa = banda(ruido(n, rng), 1300, 5500) * np.abs(pb(ruido(n, rng), 60)) * 4 * env(n, 0.03, 0.06)
    return reverb(satura(junta((golpe, 1.0, 0), (surdo(rng, 0.12, 260, 0.04), 0.3, 0),
                               (estalos(0.12, 260, rng, 700, 4000, 0.002, (0.2, 1.0)) * env(int(0.12 * TAXA), 0.002, 0.05), 0.6, 0.004),
                               (modal(rng, 900, 0.08, 12, 6, 0.001), 0.35, 0.11), (raspa, 0.5, 0.05),
                               (chiado_hidraulico(rng, 0.25, 4500, 900), 0.15, 0.16)), 2.5), 0.5, 0.18)


def impacto_estrutura_b(rng):
    """Mordida na construção (inseto mecânico): três estalos rápidos das mandíbulas roendo a chapa."""
    partes = []
    for k, at in enumerate((0.0, 0.07, 0.16)):
        partes += [(modal(rng, rng.uniform(700, 1000), 0.08, 10, 7, 0.001), 0.8 - 0.15 * k, at),
                   (estalos(0.06, 300, rng, 900, 5000, 0.0015, (0.2, 1.0)) * env(int(0.06 * TAXA), 0.001, 0.025), 0.2, at),
                   (modal(rng, 300, 0.15, 6, 6, 0.002, (150, 4000)), 0.8, at)]
    return reverb(satura(junta(*partes), 2.5), 0.45, 0.16)


def impacto_estrutura_c(rng):
    """Mordida (amassando chapa): o "chomp" surdo da mandíbula, a chapa amassando (granulado) e um rasgo curto."""
    chomp = junta((modal(rng, 240, 0.15, 3.0, 6, 0.003, (150, 3000)), 1.0, 0),
                  (banda(rosa(int(0.15 * TAXA), rng), 150, 800) * env(int(0.15 * TAXA), 0.001, 0.035), 0.5, 0))
    amassa = graos(rng, 0.22, 320, 400, 3200, 5.0, (0.0003, 0.0015), lambda u: np.sin(np.pi * min(u * 1.4, 1.0)) ** 0.7)
    n = int(0.15 * TAXA)
    rasga = banda(ruido(n, rng), 900, 3500) * np.abs(pb(ruido(n, rng), 80)) * 4 * env(n, 0.02, 0.05)
    return reverb(satura(junta((chomp, 1.0, 0), (amassa, 1.6, 0.01), (rasga, 0.4, 0.12)), 2.0), 0.4, 0.15)


def impacto_estrutura_d(rng):
    """Mordida (pistão e garra): o ar do pistão subindo, um "ka-chunk" seco das presas e a garra moendo a chapa."""
    n = int(0.09 * TAXA)
    pss = pb_varia(banda(rosa(n, rng), 600, 8000), np.linspace(900, 4500, n)) * env(n, 0.06, 0.02)
    chunk = junta((modal(rng, 280, 0.2, 3.5, 8, 0.003, (150, 5000)), 1.0, 0),
                  (banda(rosa(int(0.15 * TAXA), rng), 150, 900) * env(int(0.15 * TAXA), 0.001, 0.04), 0.5, 0))
    moe = graos(rng, 0.25, 180, 600, 3500, 6.0, (0.0004, 0.002), lambda u: 1 - u)
    return reverb(satura(junta((pss, 0.25, 0), (chunk, 1.0, 0.08), (moe, 1.1, 0.11)), 2.0), 0.45, 0.16)


def impacto(rng):
    """Impacto grande (núcleo caindo, cápsula chegando): estrondo surdo, terra voando e o chão tremendo."""
    d = 3.5
    n = int(d * TAXA)
    tremor = banda(rosa(n, rng), 90, 600) * env(n, 0.01, 0.9)
    terra = banda(rosa(int(1.5 * TAXA), rng), 250, 3000) * env(int(1.5 * TAXA), 0.003, 0.35)
    m = int(0.5 * TAXA)
    x = junta((baque(90, 32, 1.5, 0.45, 2.0), 0.22, 0), (ressoa(rosa(m, rng), 160, 2) * env(m, 0.002, 0.12), 1.4, 0), (estalo(0.06, rng, 500, 6000, 0.01), 1.4, 0), (terra, 1.6, 0.01),
              (tremor, 1.0, 0.03), (estalos(2.0, 25, rng, 800, 4000, 0.004, (0.05, 0.35)), 0.5, 0.25))
    return reverb(satura(x, 2.0), 2.2, 0.3, 2000)


def _explosao(rng, d, sub_f, rolo_q, umido, debris):
    n = int(d * TAXA)
    fogo = pb_varia(pa(rosa(n, rng), 180), 300 + 5000 * env(n, 0.003, d * 0.18)) * env(n, 0.003, d * 0.28)
    x = junta((estalo(0.05, rng, 700, 9000, 0.006), 1.5, 0), (baque(sub_f, sub_f * 0.4, d, rolo_q, 2.0), 0.3, 0), (fogo, 2.4, 0.002),
              (ressoa(rosa(n, rng), 190, 2) * env(n, 0.002, d * 0.12), 1.2, 0),
              (estalos(d * 0.7, debris, rng, 1000, 5000, 0.004, (0.05, 0.4)), 0.45, d * 0.15))
    return reverb(satura(x, 2.2), d * 1.2, umido, 2500)


def explosao(rng):
    """Explosão: estalo, bola de fogo rugindo, baque grave e pedaços caindo."""
    return _explosao(rng, 0.9, 90, 0.2, 0.28, 40)


def explosao_grande(rng):
    """Explosão grande: tudo maior, o grave mais fundo e o rolar mais longo."""
    return _explosao(rng, 1.8, 65, 0.45, 0.35, 35)


def mina_pulso(rng):
    """Mina de pulso: golpe surdo de pressão, um anel elétrico que treme e faíscas."""
    d = 0.8
    n = int(d * TAXA)
    anel = np.sin(2 * np.pi * np.cumsum(varre(900, 300, d, 2)) / TAXA + 2.5 * osc(np.full(n, 73.0))) * env(n, 0.002, 0.18)
    return reverb(junta((baque(170, 38, 0.5, 0.12, 2.5), 1.3, 0), (anel, 0.45, 0), (estalo(0.04, rng, 600, 6000, 0.005), 0.7, 0),
                        (estalos(0.4, 70, rng, 2500, 9000, 0.0015, (0.1, 0.5)), 0.35, 0.03)), 0.9, 0.3)


# ==============================================================================
# MÁQUINAS E TRENS (laços contínuos: o jogo toca em laço enquanto a máquina trabalha — Som.loop_maquina)
# ==============================================================================
def maq_fornalha(rng):
    """Fornalha: fogo rugindo no fundo, o ar puxado pela chaminé e brasas estalando."""
    d = 2.2
    n = int(d * TAXA)
    lfo = 0.75 + 0.25 * np.sin(2 * np.pi * 0.9 * tempo(d)) * np.sin(2 * np.pi * 0.37 * tempo(d) + 1)
    ronco = banda(rosa(n, rng), 90, 1000) * lfo
    ar = ressoa(banda(rosa(n, rng), 150, 900), 230, 3) * 0.4
    return junta((ronco, 1.0, 0), (ar, 0.6, 0), (estalos(d, 9, rng, 1200, 5000, 0.004, (0.1, 0.7)), 0.35, 0))


def maq_montadora(rng):
    """Montadora: servo que gira e para, prensa pneumática batendo e um clique de encaixe."""
    d = 2.0                                       # laço de 1,7 s
    n = int(d * TAXA)
    t = tempo(d)
    f = 180 + 120 * np.clip(np.sin(2 * np.pi * 0.6 * t), 0, 1)
    servo = banda(osc(f, 'serra') + 0.4 * osc(f * 2.01, 'serra'), 200, 2500) * (0.3 + 0.7 * np.clip(np.sin(2 * np.pi * 0.6 * t), 0, 1))
    prensa = lambda: junta((baque(130, 70, 0.2, 0.05), 1.0, 0), (metal([(640, 0.05, 1), (1510, 0.03, 0.5)], 0.15, rng), 0.35, 0),
                           (pb(rosa(int(0.12 * TAXA), rng), 3000) * env(int(0.12 * TAXA), 0.01, 0.04), 0.4, 0.02))
    return junta((servo, 0.35, 0), (prensa(), 0.9, 0.45), (prensa(), 0.75, 1.15),
                 (ressoa(estalo(0.03, rng, 1500, 7000, 0.0015), 2800, 8), 0.4, 0.8))


def maq_broca(rng):
    """Broca: motor grave girando e a rosca moendo pedra (ruído que pulsa na volta da rosca)."""
    d = 2.0
    n = int(d * TAXA)
    t = tempo(d)
    motor = banda(osc(np.full(n, 46.0) * (1 + 0.01 * np.sin(2 * np.pi * 0.7 * t)), 'serra'), 110, 1100)
    volta = 0.55 + 0.45 * np.sin(2 * np.pi * 6.0 * t) ** 2
    moe = banda(rosa(n, rng), 250, 2200) * volta
    return junta((motor, 0.7, 0), (moe, 1.0, 0), (estalos(d, 18, rng, 800, 3500, 0.004, (0.1, 0.5)), 0.3, 0))


def maq_esteira_a(rng):
    """Esteira (rolos e borracha): motor macio, a lona correndo e os roletes batendo de leve, sem ritmo de relógio."""
    d = 2.0
    n = int(d * TAXA)
    t = tempo(d)
    motor = sum(a * np.sin(2 * np.pi * f * t * (1 + 0.002 * np.sin(2 * np.pi * 0.5 * t))) for f, a in ((100, 0.5), (200, 0.3), (300, 0.12)))
    lona = banda(rosa(n, rng), 160, 1500) * (0.85 + 0.15 * np.sin(2 * np.pi * 0.8 * t))
    rolos = ressoa(estalos(d, 16, rng, 300, 2500, 0.004, (0.2, 1.0)), 650, 4) + 0.5 * ressoa(estalos(d, 9, rng, 300, 2500, 0.004), 1150, 5)
    return junta((motor, 0.05, 0), (lona, 0.8, 0), (rolos, 0.5, 0))


def maq_esteira_b(rng):
    """Esteira (corrente de aço): motor, lona por baixo e os elos da corrente chocalhando miúdo."""
    d = 2.0
    n = int(d * TAXA)
    t = tempo(d)
    motor = sum(a * np.sin(2 * np.pi * f * t) for f, a in ((100, 0.5), (200, 0.25)))
    lona = banda(rosa(n, rng), 160, 1200)
    elos = np.zeros(n)
    k = 0.0
    while k < d - 0.05:
        i = int(k * TAXA)
        e = modal(rng, rng.uniform(1300, 1900), 0.04, 9, 5, 0.0008, (800, 9000))
        elos[i:i + len(e)] += e * rng.uniform(0.3, 1.0)
        k += 1 / 22 * rng.uniform(0.7, 1.3)
    return junta((motor, 0.04, 0), (lona, 0.55, 0), (elos, 0.5, 0))


def apito_trem(rng):
    """Buzina do trem: acorde de três tubos levemente desafinados, ataque com ar e eco no campo."""
    d = 1.3
    n = int(d * TAXA)
    s = np.zeros(n)
    for f in (277.2, 349.2, 415.3):
        fr = f * (1 + 0.003 * np.sin(2 * np.pi * 5.1 * tempo(d) + f))
        s += osc(fr, 'serra') + 0.3 * osc(fr * 1.002, 'serra')
    s = ressoa(s, 900, 1.5) + 0.5 * ressoa(s, 1800, 2.0) + 0.4 * pb(s, 700)
    ar = banda(rosa(n, rng), 800, 4000) * env(n, 0.005, 0.08)
    x = pb(s, 5000) * env(n, 0.06, 0.18, d - 0.35) + 0.25 * ar
    return reverb(satura(x, 1.4), 1.6, 0.4, 3000)


def trem_trilho(rng):
    """Rodas no trilho: o tá-tá…tá-tá das emendas e o ronco de rolagem por baixo."""
    d = 2.3                                       # laço de 2,0 s (0,3 s vão no crossfade): emendas a cada 1,0 s
    n = int(d * TAXA)
    rolo = banda(rosa(n, rng), 110, 1000) * 0.6 + ressoa(rosa(n, rng), 170, 2) * 0.3
    batidas = np.zeros(n)
    for ini in (0.15, 1.15, 2.15):
        for k, dt in enumerate((0.0, 0.12)):
            i = int((ini + dt) * TAXA)
            b = junta((baque(210, 110, 0.12, 0.025), 0.45, 0), (metal([(760, 0.03, 1), (1720, 0.02, 0.5)], 0.08, rng), 0.5, 0))
            batidas[i:i + len(b)] += b[:n - i]
    return junta((rolo, 1, 0), (batidas, 0.9, 0))


# ==============================================================================
# CLIMA
# ==============================================================================
def chuva(rng):
    """Chuva: cortina de gotas (ruído rosa abafado) com pingos batendo perto, em laço."""
    d = 6.0
    n = int(d * TAXA)
    cortina = pb(pa(rosa(n, rng), 300), 5500) * (0.9 + 0.1 * np.sin(2 * np.pi * 0.21 * tempo(d)))
    pingos = estalos(d, 55, rng, 1800, 6500, 0.002, (0.05, 0.5))
    return junta((cortina, 1.0, 0), (pingos, 0.35, 0))


def trovao(rng):
    """Trovão: estalo do raio perto e o rolar grave que vai e volta, sumindo."""
    d = 4.5
    n = int(d * TAXA)
    t = tempo(d)
    rolos = np.zeros(n)
    for c, l in ((0.35, 0.5), (1.1, 0.7), (1.9, 0.5), (2.8, 0.35)):
        rolos += l * np.exp(-((t - c) / 0.45) ** 2)
    rolo = banda(rosa(n, rng), 55, 700) * (0.25 + rolos) * env(n, 0.02, 1.6)
    raio = pb_varia(banda(ruido(int(0.5 * TAXA), rng), 300, 9000), np.linspace(9000, 500, int(0.5 * TAXA))) * env(int(0.5 * TAXA), 0.001, 0.08)
    return reverb(satura(junta((raio, 1.0, 0), (rolo, 1.6, 0.03), (baque(60, 30, 1.5, 0.5, 1.5), 0.2, 0.05)), 1.8), 2.5, 0.3, 1800)


def vento_forte(rng):
    """Vento forte: ar passando com rajadas (o filtro abre e fecha) e o assobio nos cabos, em laço."""
    d = 6.0
    n = int(d * TAXA)
    t = tempo(d)
    rajada = 0.6 + 0.4 * np.sin(2 * np.pi * 0.17 * t) * np.sin(2 * np.pi * 0.41 * t + 1.3)
    ar = pb_varia(pa(rosa(n, rng), 120), 350 + 1500 * rajada) * rajada
    assobio = ressoa(rosa(n, rng), 1150 + 120 * np.sin(2 * np.pi * 0.23 * t).mean(), 40) * np.clip(rajada - 0.55, 0, 1)
    return junta((ar, 1.0, 0), (assobio, 0.5, 0), (pb(rosa(n, rng), 120), 0.5, 0))


# ==============================================================================
# ARANHAS
# ==============================================================================
def _pe(rng, ponta_f, q, terra_g, peso_g):
    """Um pé tocando o chão: a ponta (metal batido), a terra esmagando embaixo e o peso da perna."""
    n = int(0.06 * TAXA)
    terra = banda(rosa(n, rng), 300, 2800) * env(n, 0.0008, 0.016)
    return junta((modal(rng, ponta_f, 0.1, q, 7, 0.0012, (400, 7000)), 0.55, 0), (terra, terra_g, 0),
                 (estalos(0.05, 220, rng, 900, 3500, 0.0012, (0.05, 0.4)), terra_g * 0.4, 0.002), (surdo(rng, 0.08, 230, 0.025), peso_g, 0))


def aranha_passo_a(rng):
    """Passo (mecânica pesada): o servo empurra, um chiado curto de hidráulica e os três pés do trípode pousando
    quase juntos (cada um com sua ponta de aço, a terra e o peso)."""
    servo = banda(osc(varre(330, 470, 0.09, 1.0), 'serra'), 300, 2400) * env(int(0.09 * TAXA), 0.012, 0.03)
    return reverb(junta((servo, 0.08, 0), (chiado_hidraulico(rng, 0.08, 4000, 1500), 0.06, 0),
                        (_pe(rng, 480, 11, 0.9, 0.8), 1.0, 0.03), (_pe(rng, 520, 11, 0.8, 0.7), 0.8, 0.046),
                        (_pe(rng, 450, 11, 0.7, 0.6), 0.65, 0.061)), 0.3, 0.1)


def aranha_passo_b(rng):
    """Passo (inseto mecânico): três toques secos de carapaça na terra, rápidos e leves."""
    return reverb(junta((_pe(rng, 900, 6, 0.6, 0.2), 1.0, 0), (_pe(rng, 1000, 6, 0.5, 0.18), 0.75, 0.018),
                        (_pe(rng, 860, 6, 0.5, 0.15), 0.6, 0.034)), 0.25, 0.08)


def aranha_passo_c(rng):
    """Passo (terra e peso): os três pés do trípode esmagando a terra e o peso de cada perna, sem metal tocando."""
    partes = []
    for k, at in enumerate((0.0, rng.uniform(0.012, 0.022), rng.uniform(0.028, 0.042))):
        partes += [(graos(rng, 0.035, 55, 350, 2800, 3.0, forma=lambda u: np.exp(-3 * u)), 1.6 - 0.3 * k, at),
                   (banda(rosa(int(0.06 * TAXA), rng), 160, 700) * env(int(0.06 * TAXA), 0.001, 0.02), 0.6 - 0.12 * k, at),
                   (modal(rng, rng.uniform(300, 380), 0.06, 2.5, 4, 0.002, (150, 2000)), 0.35 - 0.06 * k, at)]
    return reverb(junta(*partes), 0.25, 0.08)


def aranha_passo_d(rng):
    """Passo (pata de aço abafada): um "tuc" seco de aço bem amortecido em cada pé, com um pouco de terra."""
    partes = []
    for k, at in enumerate((0.0, rng.uniform(0.010, 0.018), rng.uniform(0.024, 0.034))):
        partes += [(modal(rng, rng.uniform(420, 560), 0.05, 3.0, 6, 0.0012, (300, 5000)), 1.0 - 0.2 * k, at),
                   (graos(rng, 0.02, 15, 500, 3000, 3.0, forma=lambda u: 1 - u), 0.5, at + 0.002),
                   (banda(rosa(int(0.05 * TAXA), rng), 180, 900) * env(int(0.05 * TAXA), 0.001, 0.015), 0.4 - 0.08 * k, at)]
    return reverb(junta(*partes), 0.25, 0.08)


def aranha_passo_e(rng):
    """Passo (toque leve): as três pontas mal encostando no chão, um tique miúdo cada, quase nada de corpo."""
    partes = []
    for k, at in enumerate((0.0, rng.uniform(0.014, 0.024), rng.uniform(0.03, 0.045))):
        partes += [(graos(rng, 0.008, 5, 1300, 4200, 2.5, (0.0003, 0.0008), lambda u: 1 - u), 1.0 - 0.25 * k, at),
                   (modal(rng, rng.uniform(950, 1300), 0.03, 2.0, 4, 0.0008, (600, 5000)), 0.25 - 0.05 * k, at)]
    return reverb(junta(*partes), 0.2, 0.06)


def aranha_passo_f(rng):
    """Passo (roçar): as pernas varrendo a terra de leve, um sussurro de cascalho fino."""
    n = int(0.09 * TAXA)
    roca = banda(rosa(n, rng), 900, 5000) * env(n, 0.012, 0.025)
    return reverb(junta((roca, 0.5, 0), (graos(rng, 0.06, 10, 1000, 3500, 3.0, (0.0003, 0.001), lambda u: np.sin(np.pi * u)), 1.0, 0.005)),
                  0.2, 0.06)


def _desaba(rng, inicio):
    """As seis pernas cedendo uma atrás da outra e o corpo batendo no chão, com terra e cascalho."""
    partes = []
    for k, at in enumerate((0.0, 0.07, 0.15, 0.19, 0.28, 0.35)):
        partes.append((modal(rng, rng.uniform(280, 460), 0.18, 8, 8, 0.002, (150, 6000)), rng.uniform(0.4, 0.8), inicio + at))
    partes += [(surdo(rng, 0.4, 260, 0.09), 0.5, inicio + 0.22), (modal(rng, 190, 0.35, 6, 8, 0.004, (100, 4000)), 0.9, inicio + 0.22),
               (banda(rosa(int(0.4 * TAXA), rng), 250, 2500) * env(int(0.4 * TAXA), 0.002, 0.08), 0.7, inicio + 0.23),
               (estalos(0.5, 50, rng, 900, 4000, 0.003, (0.05, 0.4)), 0.4, inicio + 0.3)]
    return partes


def aranha_morre_a(rng):
    """Morte (mecânica pesada): curto-circuito estalando, o motor perdendo força (série harmônica que cai devagar),
    o pistão soltando o ar e a carcaça desabando."""
    d = 0.9
    n = int(d * TAXA)
    f0 = 210 * np.exp(-tempo(d) / 0.5) + 30
    motor = sum(osc(f0 * k) / k for k in range(1, 11))
    motor = banda(motor, 160, 2600) * env(n, 0.005, 0.35)
    m = int(0.35 * TAXA)
    zum = banda(osc(np.full(m, 50.0), 'quad'), 100, 2500) * env(m, 0.002, 0.12)
    return reverb(satura(junta((estalos(0.3, 160, rng, 2500, 9000, 0.0012, (0.2, 1.0)), 0.5, 0), (zum, 0.2, 0),
                               (motor, 0.55, 0.02), (chiado_hidraulico(rng, 0.45, 5000, 600), 0.35, 0.25),
                               *_desaba(rng, 0.5)), 1.4), 0.6, 0.18)


def aranha_morre_b(rng):
    """Morte (inseto mecânico): estalo elétrico, as juntas travando em rajada e a carcaça caindo seca."""
    juntas = np.zeros(int(0.35 * TAXA))
    k = 0.0
    while k < 0.3:
        e = modal(rng, rng.uniform(800, 1400), 0.03, 9, 6, 0.0008)
        i = int(k * TAXA)
        juntas[i:i + len(e)] += e[:len(juntas) - i] * rng.uniform(0.3, 1.0)
        k += rng.uniform(0.015, 0.035)
    return reverb(satura(junta((estalo(0.04, rng, 1500, 9000, 0.004), 1.0, 0), (estalos(0.2, 140, rng, 3000, 9000, 0.001), 0.4, 0),
                               (juntas, 0.6, 0.04), *_desaba(rng, 0.38)), 2.2), 0.5, 0.16)


# ==============================================================================
# CENAS
# ==============================================================================
def reentrada(rng):
    """Reentrada do núcleo: o ar rasgando em volta da cápsula, crescendo e ficando mais agudo até o fim."""
    d = 5.0
    n = int(d * TAXA)
    t = tempo(d)
    cresce = (t / d) ** 1.6
    rasgo = pb_varia(rosa(n, rng), 300 + 3500 * cresce) * (0.2 + 0.8 * cresce)
    ronco = pb(rosa(n, rng), 140) * (0.3 + 0.7 * cresce)
    fogo = estalos(d, 30, rng, 800, 4000, 0.004, (0.05, 0.4)) * cresce
    return junta((rasgo, 1.0, 0), (ronco, 0.8, 0), (fogo, 0.5, 0))


def fogo(rng):
    """Fogo (árvore queimando): chama soprando e crepitar de madeira, em laço."""
    d = 3.0
    n = int(d * TAXA)
    chama = pb(rosa(n, rng), 700) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.8 * tempo(d)) ** 2)
    return junta((chama, 1.0, 0), (estalos(d, 22, rng, 700, 4000, 0.006, (0.1, 1.0)), 0.45, 0),
                 (estalos(d, 6, rng, 300, 1500, 0.015, (0.3, 1.0)), 0.3, 0))


def faisca(rng):
    """Faísca: curto-circuito estalando, com um zumbido de 60 Hz por trás."""
    d = 0.4
    n = int(d * TAXA)
    zum = banda(osc(np.full(n, 60.0), 'quad'), 120, 3000) * env(n, 0.005, 0.1)
    return reverb(junta((estalos(0.3, 80, rng, 2000, 8000, 0.0012, (0.2, 1.0)), 0.8, 0), (zum, 0.25, 0)), 0.3, 0.12)


# ==============================================================================
# nome, função, alvo (dB do pico de curto prazo), laço (s de crossfade; 0 = som único), fade de entrada (s)
# ==============================================================================
# FAUNA (patch fauna): cantos por espécie e a revoada
# ==============================================================================
def silaba(rng, fs, harm=(1.0, 0.22, 0.06), sopro=0.07, vib=(0.0, 0.0), ataque=0.004, queda=0.02, aspero=0.0):
    """Sílaba de canto: tom com a curva de frequência `fs` (Hz por amostra), harmônicos fracos, vibrato, um pouco de
    sopro (ruído na mesma banda) e jitter de altura — a siringe não é um oscilador perfeito."""
    fs = np.asarray(fs, dtype=float)
    n = len(fs)
    t = np.arange(n) / TAXA
    jit = 1.0 + 0.006 * np.interp(np.arange(n), np.linspace(0, n, 12), rng.standard_normal(12))   # deriva lenta da altura
    f = fs * jit * (1.0 + vib[1] * np.sin(2 * np.pi * vib[0] * t))
    x = sum(a * osc(f * (k + 1)) for k, a in enumerate(harm))
    if aspero > 0.0:                                     # chiado da garganta (canto áspero, grito)
        x *= 1.0 + aspero * banda(ruido(n, rng), 60, 400) * 3
    fm = float(np.median(fs))
    x += sopro * banda(ruido(n, rng), fm * 0.7, fm * 1.4) * 4
    borda = min(n // 2 - 1, int(0.004 * TAXA))             # rampas de 4 ms (sem estalo no começo/fim da nota)
    jan = np.ones(n)
    if borda > 1:
        r = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, borda))
        jan[:borda] = r
        jan[-borda:] = r[::-1]
    return x * env(n, ataque, queda, 0.6) * jan


def frase(rng, notas, gap_s):
    """Junta sílabas com pausas (cada uma com o seu volume)."""
    partes, t0 = [], 0.0
    for x, vol in notas:
        partes.append((x, vol, t0))
        t0 += len(x) / TAXA + gap_s * rng.uniform(0.8, 1.25)
    return junta(*partes)


def pardelo_canto(rng):
    """Pardelo: dois ou três "tchip" curtos descendo e um "tchrr" chiado no fim (pássaro de bando, conversa)."""
    notas = []
    for i in range(rng.integers(2, 4)):
        f0 = rng.uniform(4300, 5000)
        notas.append((silaba(rng, varre(f0, f0 * 0.72, rng.uniform(0.05, 0.07), 1.8), (1.0, 0.3, 0.1), 0.1), 1.0))
    notas.append((silaba(rng, varre(3900, 3500, 0.11), (1.0, 0.4, 0.2), 0.25, (85, 0.06), aspero=0.5), 0.6))
    return reverb(frase(rng, notas, 0.07), 0.45, 0.14, 7000)


def cobrico_canto(rng):
    """Cobrico: trinado rápido e agudo (notas de 25 ms alternando e subindo), como um canário miúdo."""
    notas = []
    base = rng.uniform(5200, 5800)
    for i in range(rng.integers(10, 16)):
        f = base * (1.0 + 0.012 * i) * (1.1 if i % 2 else 1.0)
        notas.append((silaba(rng, varre(f * 0.92, f, 0.026, 0.7), (1.0, 0.15), 0.05, ataque=0.002, queda=0.006), 0.8 + 0.2 * (i % 2)))
    return reverb(frase(rng, notas, 0.012), 0.45, 0.14, 8000)


def azulao_canto(rng):
    """Azulão: assobio melódico, notas ligadas e cheias com vibrato (frase de 4–5 notas)."""
    notas = []
    f = rng.uniform(2300, 2700)
    for i in range(rng.integers(4, 6)):
        f1 = f * rng.choice([0.84, 1.12, 1.26, 0.94, 1.19])
        notas.append((silaba(rng, varre(f, f1, rng.uniform(0.11, 0.2), 0.6), (1.0, 0.12, 0.03), 0.04, (6.5, 0.012),
                             ataque=0.012, queda=0.04), 1.0))
        f = min(3800, max(2100, f1))
    return reverb(frase(rng, notas, 0.035), 0.5, 0.16, 6000)


def rubro_canto(rng):
    """Rubro: "tiú-tiú-tiú" forte e limpo, cada nota descendo (chamado de território)."""
    notas = []
    for i in range(rng.integers(3, 5)):
        f0 = rng.uniform(3600, 4000) * (1 - 0.03 * i)
        notas.append((silaba(rng, varre(f0, f0 * 0.6, 0.15, 1.4), (1.0, 0.2, 0.05), 0.05, ataque=0.006, queda=0.05), 1.0))
    return reverb(frase(rng, notas, 0.09), 0.5, 0.15, 6500)


def planador_grito(rng):
    """Planador-cinza: grito alto e longo que cai ("kiii-aaa"), áspero, ecoando (ave grande, longe)."""
    d = rng.uniform(0.8, 1.05)
    f0 = rng.uniform(3000, 3300)
    fs = np.concatenate([varre(f0 * 0.85, f0, 0.12, 0.5), varre(f0, f0 * 0.62, d - 0.12, 1.6)])
    x = silaba(rng, fs, (1.0, 0.45, 0.25, 0.12), 0.12, (11, 0.01), ataque=0.03, queda=0.25, aspero=0.35)
    return reverb(x, 1.1, 0.3, 5000)


def revoada(rng):
    """Bando levantando voo: batidas de asa (pulsos de ruído largo a ~16/s por pássaro) de vários pássaros
    desencontrados, que sobem e somem; um ou dois piados de susto."""
    d = 1.3
    n = int(d * TAXA)
    t = tempo(d)
    x = np.zeros(n)
    for k in range(int(rng.integers(5, 9))):
        t0 = rng.uniform(0.0, 0.25)
        bat = rng.uniform(13, 19)
        fase = (t - t0) * bat
        pulso = np.where(t > t0, np.clip(np.sin(2 * np.pi * fase), 0, 1) ** 6, 0.0)
        some = np.clip(1.0 - (t - t0) / rng.uniform(0.7, 1.1), 0, 1) ** 1.5
        x += banda(rosa(n, rng), rng.uniform(500, 900), rng.uniform(3500, 6000)) * pulso * some * rng.uniform(0.6, 1.0)
    piado = silaba(rng, varre(5000, 3600, 0.06, 1.5), (1.0, 0.3), 0.1)
    return reverb(junta((x, 1.0, 0), (piado, 0.35, rng.uniform(0.05, 0.3))), 0.4, 0.12, 6000)


def solda_arco(rng):
    """Solda a arco (braço do drone construtor): zumbido elétrico de 100 Hz + chiado frito com estouros ao acaso,
    que oscila com o movimento da tocha. Alterna com solda_mig enquanto o drone trabalha."""
    d = 0.9
    n = int(d * TAXA)
    t = tempo(d)
    zumbido = pb(osc(100, 'quad') * 0.5 + osc(200, 'serra') * 0.3, 1400) * 0.25
    frito = banda(ruido(n, rng), 1800, 9000) * (0.55 + 0.45 * np.abs(np.sin(2 * np.pi * 3.3 * t + rng.uniform(0, 6))))
    pops = estalos(d, 55, rng, 2000, 9000, 0.0015, (0.3, 1.0))
    x = (zumbido + frito * 0.45 + pops * 0.7) * env(n, 0.02, 0.1, d - 0.15)
    return reverb(x, 0.25, 0.08)


def solda_mig(rng):
    """Solda MIG: fritura densa e contínua (centenas de microestalos), mais grave e encorpada, com o sopro do gás e
    quase sem zumbido. Alterna com solda_arco."""
    d = 0.9
    n = int(d * TAXA)
    t = tempo(d)
    fritura = estalos(d, 420, rng, 1200, 7000, 0.0008, (0.2, 1.0))
    gas = banda(rosa(n, rng), 300, 2500) * 0.25
    zum = pb(osc(120, 'quad'), 900) * 0.08
    x = (fritura + gas + zum) * env(n, 0.03, 0.1, d - 0.16) * (0.75 + 0.25 * np.sin(2 * np.pi * 2.1 * t))
    return reverb(x, 0.25, 0.08)


# ==============================================================================
# PATCH FAUNA, FASE 1: AMBIENTE VIVO (grilos, insetos de dia, sapos)
# ==============================================================================
def amb_grilos(rng):
    """Grilos à noite (laço): coro de uns 12 grilos, cada um com o seu tom (3,9–5,2 kHz), o seu trilo (3 a 5 pulsos
    a ~30/s) e o seu ritmo; os longe são mais baixos e abafados. Um deles, de outro mundo mas pé no chão, trila
    mais grave e devagar. Ar da noite bem baixo por baixo."""
    d = 9.0
    n = int(d * TAXA)
    t = tempo(d)
    x = np.zeros(n)
    L = int(0.022 * TAXA)
    jan = np.sin(np.linspace(0, np.pi, L)) ** 2
    for k in range(13):
        estranho = k == 12
        f = rng.uniform(2300, 2600) if estranho else rng.uniform(3900, 5200)
        perto = rng.uniform(0.25, 1.0)
        taxa = rng.uniform(14, 18) if estranho else rng.uniform(26, 38)
        pulsos = int(rng.integers(5, 8)) if estranho else int(rng.integers(3, 6))
        per = rng.uniform(1.4, 2.2) if estranho else rng.uniform(0.45, 1.1)
        en = np.zeros(n)
        tc = rng.uniform(0, per)
        while tc < d:
            for p in range(pulsos):
                i0 = int((tc + p / taxa) * TAXA)
                if i0 + L < n:
                    en[i0:i0 + L] += jan * (1.0 - 0.08 * p)
            tc += per * rng.uniform(0.92, 1.08)
        som = np.sin(2 * np.pi * f * t + 0.6 * np.sin(2 * np.pi * f * 2.003 * t)) * en
        som = pb(som, 3500 + 6000 * perto) * (0.2 + 0.8 * perto) ** 2
        x += som * (0.6 if estranho else 1.0)
    x += pb(rosa(n, rng), 700) * 0.015
    return reverb(x, 0.9, 0.22, 7000)


def amb_insetos_dia(rng):
    """Insetos de dia (laço): duas cigarras longe que crescem e somem (ruído agudo pulsando a ~190 Hz), uma mosca
    que passa zumbindo perto (serra grave com o tom mexendo) e o ar morno do campo."""
    d = 9.0
    n = int(d * TAXA)
    t = tempo(d)
    x = np.zeros(n)
    for k in range(2):
        t0, sobe, fica, desce = rng.uniform(0.3, 3.5), rng.uniform(1.2, 2.0), rng.uniform(1.5, 3.0), rng.uniform(1.0, 1.8)
        en = np.clip((t - t0) / sobe, 0, 1) * np.clip(1 - (t - t0 - sobe - fica) / desce, 0, 1)
        am = (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(170, 210) * t)) ** 3
        cig = banda(ruido(n, rng), rng.uniform(3600, 4200), rng.uniform(6000, 7000)) * am * en
        x += pb(cig, 6500) * rng.uniform(0.35, 0.6)
    ft = 210 * (1 + 0.04 * np.sin(2 * np.pi * 1.7 * t) + 0.02 * np.sin(2 * np.pi * 5.3 * t))
    fase = np.cumsum(ft) / TAXA
    mosca = pb(2 * (fase % 1.0) - 1.0, 1800)
    passa = np.exp(-((t - rng.uniform(3.0, 6.0)) / 0.9) ** 2)
    x += mosca * passa * 0.18
    x += banda(rosa(n, rng), 200, 3000) * 0.03
    return reverb(x, 0.6, 0.15, 7000)


def sapo(rng):
    """Sapo na beira d'água depois da chuva: 2 a 4 coaxos graves — pulsos estreitos (~85–120/s) passando pelas
    ressonâncias da bolsa vocal (~450 Hz, ~1,2 kHz), cada coaxo subindo e descendo um pouco o tom."""
    partes = []
    at = 0.0
    f0 = rng.uniform(85, 120)
    for c in range(int(rng.integers(2, 5))):
        d = rng.uniform(0.16, 0.28)
        nn = int(d * TAXA)
        tt = tempo(d)
        f = f0 * (1 + 0.08 * np.sin(np.pi * tt / d))
        fase = np.cumsum(f) / TAXA
        pulso = pb((np.sin(2 * np.pi * fase) > 0.6).astype(float), 4000)
        s = ressoa(pulso, rng.uniform(420, 520), 6) + ressoa(pulso, rng.uniform(1100, 1400), 5) * 0.5 \
            + ressoa(pulso, 2400, 4) * 0.2
        s = s * env(nn, 0.015, 0.06, d * 0.6)
        k = int(0.03 * TAXA)                             # fecha a boca sem estalo
        s[-k:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k))
        partes.append((s, rng.uniform(0.8, 1.0), at))
        at += d + rng.uniform(0.08, 0.16)
    return reverb(junta(*partes), 0.7, 0.2)


SONS = [
    ('clique', clique, -22, 0, 0.0005), ('construir', construir, -15, 0, 0.0005), ('remover', remover, -17, 0, 0.0005),
    ('alerta', alerta, -14, 0, 0.005), ('pesquisa', pesquisa, -15, 0, 0.001), ('derrota', derrota, -14, 0, 0.01),
    ('tiro_metralhadora', tiro_metralhadora, -14, 0, 0.0003), ('tiro', tiro, -14, 0, 0.0003),
    ('tiro_perfurante', tiro_perfurante, -13, 0, 0.0003), ('tiro_carregada', tiro_carregada, -13, 0, 0.0003),
    ('tiro_energia', tiro_energia, -13, 0, 0.0005), ('tiro_foguete', tiro_foguete, -12, 0, 0.0005),
    ('tiro_enxame', tiro_enxame, -12, 0, 0.0005), ('tiro_artilharia', tiro_artilharia, -8, 0, 0.0003),
    ('tiro_drone', tiro_drone, -15, 0, 0.0003), ('cuspe_acido', cuspe_acido, -14, 0, 0.002),
    ('acido_respingo', acido_respingo, -15, 0, 0.0005),
    ('impacto_aranha', impacto_aranha_a, -17, 0, 0.0003), ('impacto_chao', impacto_chao, -16, 0, 0.0003),
    ('impacto_estrutura', impacto_estrutura_d, -15, 0, 0.0003), ('impacto', impacto, -9, 0, 0.0005),
    ('explosao', explosao, -9, 0, 0.0005), ('explosao_grande', explosao_grande, -6.5, 0, 0.0005),
    ('mina_pulso', mina_pulso, -11, 0, 0.0005),
    ('maq_fornalha', maq_fornalha, -20, 0.3, 0), ('maq_montadora', maq_montadora, -17, 0.3, 0),
    ('maq_broca', maq_broca, -18, 0.3, 0), ('maq_esteira', maq_esteira_a, -20, 0.3, 0),
    ('apito_trem', apito_trem, -13, 0, 0.01), ('trem_trilho', trem_trilho, -17, 0.3, 0),
    ('chuva', chuva, -20, 0.5, 0), ('trovao', trovao, -11, 0, 0.0005), ('vento_forte', vento_forte, -18, 0.6, 0),
    ('aranha_passo', aranha_passo_e, -30, 0, 0.0003), ('aranha_morre', aranha_morre_b, -14, 0, 0.003),
    ('reentrada', reentrada, -12, 0, 0.3), ('fogo', fogo, -21, 0.4, 0), ('faisca', faisca, -18, 0, 0.0005),
    ('pardelo_canto', pardelo_canto, -24, 0, 0.002), ('cobrico_canto', cobrico_canto, -25, 0, 0.002),
    ('azulao_canto', azulao_canto, -23, 0, 0.004), ('rubro_canto', rubro_canto, -23, 0, 0.003),
    ('planador_grito', planador_grito, -21, 0, 0.01), ('revoada', revoada, -18, 0, 0.003),
    ('solda_arco', solda_arco, -20, 0, 0.002), ('solda_mig', solda_mig, -20, 0, 0.002),
    ('amb_grilos', amb_grilos, -24, 0.6, 0), ('amb_insetos_dia', amb_insetos_dia, -27, 0.6, 0),
    ('sapo', sapo, -17, 0, 0.003),
]


VARIACOES = {'aranha_passo': 4, 'pardelo_canto': 3, 'cobrico_canto': 3, 'azulao_canto': 3, 'rubro_canto': 2,
             'planador_grito': 2, 'revoada': 2, 'sapo': 3}       ## nome → quantos arquivos (nome.wav, nome__2.wav…): o jogo sorteia um a cada vez


if __name__ == '__main__':
    alvos = sys.argv[1:]
    for k, (nome, func, alvo, laco_s, fi) in enumerate(SONS):
        if alvos and nome not in alvos:
            continue
        fo = 0.25 if nome.startswith(('maq_', 'trem_')) else (0.08 if nome == 'reentrada' else 0.02)
        for v in range(VARIACOES.get(nome, 1)):
            x = finalizar(func(np.random.default_rng(1000 + k + 97 * v)), alvo, laco_s, fi, fo)
            gravar(nome + ('__%d' % (v + 1) if v else ''), x)
        print('SOM %-18s %5.2f s  alvo %5.1f dB%s' % (nome, len(x) / TAXA, alvo, '  (laço)' if laco_s else ''))
