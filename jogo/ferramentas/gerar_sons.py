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


def filhotes(rng):
    """Filhotes no ninho pedindo comida (fase 6): 3 ou 4 bicos abertos, cada um num "tsi" fino e insistente (40–60 ms, 6,5–8 kHz,
    subindo um pouco), 6 a 9 por segundo, desencontrados; um adulto chega e o coro aperta."""
    d = 1.8
    partes = []
    for v in range(int(rng.integers(3, 5))):
        f0 = rng.uniform(6500, 7600)
        taxa = rng.uniform(6.0, 9.0)
        t0 = rng.uniform(0.0, 0.15)
        while t0 < d - 0.06:
            dd = rng.uniform(0.04, 0.06)
            s = silaba(rng, varre(f0 * 0.94, f0 * rng.uniform(1.0, 1.06), dd, 0.8), (1.0, 0.12), 0.08,
                       ataque=0.003, queda=0.01)
            aperta = 1.0 + 0.6 * np.clip((t0 - 0.6) / 0.4, 0, 1)        # o adulto chegou: mais forte e mais rápido
            partes.append((s, rng.uniform(0.5, 0.9) * min(aperta, 1.4), t0))
            t0 += (1.0 / taxa) / aperta * rng.uniform(0.8, 1.2)
    return reverb(junta(*partes), 0.35, 0.12, 9000)


def geado_canto(rng):
    """GEADO (inverno, bando grande no chão aberto): trinado rolado e macio "tirrrr" (notas de 22 ms a ~30/s em
    volta de 3,4 kHz, caindo um pouco) e um "tiu" assobiado no fim; o chamado de contato dos bandos do frio."""
    notas = []
    base = rng.uniform(3200, 3600)
    for i in range(int(rng.integers(9, 14))):
        f = base * (1.0 - 0.008 * i)
        notas.append((silaba(rng, varre(f * 1.06, f * 0.94, 0.022, 1.0), (1.0, 0.18), 0.06, ataque=0.003, queda=0.006),
                      0.7 + 0.3 * np.sin(np.pi * i / 10)))
    tiu = silaba(rng, varre(base * 1.25, base * 0.85, 0.14, 1.3), (1.0, 0.12), 0.05, (7, 0.01), ataque=0.01, queda=0.05)
    x = frase(rng, notas, 0.011)
    x = junta((x, 1.0, 0.0), (tiu, 0.8, len(x) / TAXA + 0.09))
    return reverb(x, 0.55, 0.16, 6500)


def bando_migrando(rng):
    """Bando migrando ALTO por cima: dezenas de chamados de contato curtos e fracos ("tsii", "tiu"), desencontrados,
    sem batida de asa audível (está longe), com o agudo cortado pela distância e eco largo de céu aberto; passa
    crescendo e some (5 s)."""
    d = 5.0
    n = int(d * TAXA)
    passa = np.sin(np.pi * np.clip(np.arange(n) / n, 0, 1)) ** 1.6     # vem, passa por cima e vai
    partes = []
    for k in range(int(rng.integers(40, 60))):
        t0 = rng.uniform(0.1, d - 0.3)
        f0 = rng.uniform(3800, 6200)
        if rng.uniform() < 0.6:
            s = silaba(rng, varre(f0, f0 * rng.uniform(0.75, 0.9), rng.uniform(0.05, 0.09), 1.4), (1.0, 0.2), 0.08)
        else:
            s = silaba(rng, varre(f0 * 0.8, f0, rng.uniform(0.06, 0.1), 0.7), (1.0, 0.15), 0.05)
        partes.append((s, rng.uniform(0.3, 1.0) * float(passa[int(t0 * TAXA)]), t0))
    x = junta(*partes)
    x = pb(x, 5200, 2)                                                # o agudo some com a distância
    sopro = banda(rosa(len(x), rng), 300, 1800) * 0.04 * np.interp(np.arange(len(x)), np.arange(n), passa)
    return reverb(x + sopro, 1.4, 0.35, 4500)


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


def _mosca(rng, t, f0, voos):
    """Uma mosca: asa batendo (serra com os formantes do corpo) que muda de tom e de volume conforme chega perto e
    se afasta (Doppler de quem passa), só nos trechos em que está voando (`voos`)."""
    ft = f0 * (1 + 0.035 * np.sin(2 * np.pi * rng.uniform(0.6, 1.4) * t + rng.uniform(0, 6))
                 + 0.02 * np.sin(2 * np.pi * rng.uniform(3, 6) * t + rng.uniform(0, 6)))
    fase = np.cumsum(ft) / TAXA
    serra = 2 * (fase % 1.0) - 1.0
    asa = ressoa(serra, rng.uniform(700, 900), 3) + ressoa(serra, rng.uniform(1500, 1900), 4) * 0.5 + pb(serra, 1200) * 0.6
    perto = 0.55 + 0.45 * np.sin(2 * np.pi * rng.uniform(0.25, 0.5) * t + rng.uniform(0, 6))
    return asa * voos * perto ** 2


def _voos(rng, n, d, cheio):
    """Envelope de voo: 1 voando, 0 pousada (rampa de 40 ms: decola e pousa sem estalo)."""
    t = 0.0
    v = np.zeros(n)
    voando = rng.random() < 0.5
    while t < d:
        dur = rng.uniform(1.2, 3.5) if voando else rng.uniform(0.3, 1.8) * (0.3 if cheio else 1.0)
        a, b = int(t * TAXA), int(min(d, t + dur) * TAXA)
        if voando:
            v[a:b] = 1.0
        t += dur
        voando = not voando
    k = int(0.04 * TAXA)
    return np.convolve(v, np.ones(k) / k, mode='same')


def amb_moscas(rng):
    """Moscas em cima da carcaça (laço, patch fauna fase 4): 5 varejeiras graves (~140–185 Hz) quase sempre no ar,
    uma por cima da outra, e o ar do campo por baixo."""
    d = 8.0
    n = int(d * TAXA)
    t = tempo(d)
    x = np.zeros(n)
    for k in range(5):
        x += _mosca(rng, t, rng.uniform(140, 185), _voos(rng, n, d, True)) * rng.uniform(0.5, 1.0)
    x += banda(rosa(n, rng), 200, 2500) * 0.02
    return reverb(x, 0.5, 0.12, 6000)


def rato_chiado(rng):
    """Rato (patch fauna, fase 5): trinado agudo — 2 a 4 piados curtos (30 a 60 ms) que sobem e descem entre 6 e 9 kHz."""
    partes = []
    at = 0.0
    for k in range(int(rng.integers(2, 5))):
        d = rng.uniform(0.03, 0.06)
        t = tempo(d)
        f0, f1 = rng.uniform(6000, 7200), rng.uniform(7500, 9000)
        f = f0 + (f1 - f0) * np.sin(np.pi * t / d)
        s = np.sin(2 * np.pi * np.cumsum(f) / TAXA) * np.sin(np.pi * t / d) ** 1.5
        partes.append((s, rng.uniform(0.6, 1.0), at))
        at += d + rng.uniform(0.02, 0.07)
    return reverb(junta(*partes), 0.35, 0.12, 9000)


def rato_guincho(rng):
    """Rato (fase 5), a outra voz: um ou dois guinchos mais longos (~0,12 s) e anasalados — tom de ~3,8 kHz com
    harmônicos passando por uma ressonância, que treme (vibrato rápido) e cai no fim."""
    partes = []
    at = 0.0
    for k in range(int(rng.integers(1, 3))):
        d = rng.uniform(0.09, 0.15)
        t = tempo(d)
        f = rng.uniform(3500, 4100) * (1 + 0.04 * np.sin(2 * np.pi * 38 * t)) * (1 - 0.12 * (t / d) ** 2)
        fase = np.cumsum(f) / TAXA
        s = np.sin(2 * np.pi * fase) + 0.35 * np.sin(4 * np.pi * fase) + 0.15 * np.sin(6 * np.pi * fase)
        s = ressoa(s, rng.uniform(4200, 5200), 3) * 0.6 + s * 0.4
        s *= env(len(t), 0.008, 0.04, d * 0.6)
        partes.append((s, rng.uniform(0.7, 1.0), at))
        at += d + rng.uniform(0.05, 0.12)
    return reverb(junta(*partes), 0.35, 0.12, 9000)


def rato_cavar(rng):
    """Rato cavando (enterra a semente): as unhas raspam a terra em rajadas rápidas (~6 por segundo) e torrões caem."""
    d = 1.2
    n = int(d * TAXA)
    x = np.zeros(n)
    for k in range(7):
        t0 = k / 6.0 + rng.uniform(-0.02, 0.02)
        dur = rng.uniform(0.06, 0.1)
        a, b = int(t0 * TAXA), int(min(d, t0 + dur) * TAXA)
        if a >= n:
            break
        x[a:b] += banda(ruido(b - a, rng), 1800, 6000) * np.hanning(b - a) ** 0.7 * rng.uniform(0.6, 1.0)
    g = graos(rng, d, 26, 300, 1500, q=3.0)
    x[:min(n, len(g))] += g[:min(n, len(g))] * 0.5
    return reverb(x, 0.3, 0.1, 6000)


def rato_roendo(rng):
    """Rato roendo cabo (fase 7): dentes raspando: rajadas de 6 a 10 cliques secos e agudos (3–7 kHz) a ~11 por segundo, com pausas curtas
    entre as rajadas (ele para, olha e volta a roer)."""
    partes = []
    at = 0.0
    for r in range(int(rng.integers(3, 5))):
        for k in range(int(rng.integers(6, 11))):
            d = rng.uniform(0.012, 0.022)
            n = int(d * TAXA)
            x = banda(ruido(n, rng), rng.uniform(2800, 3600), rng.uniform(6000, 7500)) * np.hanning(n) ** 0.5
            x = x * 0.7 + ressoa(x, rng.uniform(3800, 4600), 6) * 0.5
            partes.append((x, rng.uniform(0.6, 1.0), at))
            at += 1.0 / rng.uniform(10.0, 12.5)
        at += rng.uniform(0.18, 0.4)
    return reverb(junta(*partes), 0.25, 0.08, 8000)


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


# ==============================================================================
# PATCH FAUNA, FASE 9: FAUNA GRANDE (manada e predador), PEIXES E ENXAMES
# ==============================================================================
def glote(rng, f0s, jitter=0.01, tremor=0.08, dobra=0.0, sopro=0.1, tilt=800, ordem=1):
    """Fonte da voz de mamífero: um pulso por ciclo das pregas vocais, com jitter (o período nunca repete igual) e
    tremor (a força de cada pulso também não), a queda natural dos agudos (`tilt`) e o ar passando junto, no ritmo
    do ciclo. `dobra` enfraquece um pulso sim, outro não: aparece o sub-harmônico da voz rouca, quebrada.
    `sopro` pode ser uma curva (o ar que aumenta quando o bicho força a voz)."""
    f0s = np.asarray(f0s, dtype=float)
    n = len(f0s)
    k = max(4, int(n / TAXA * 30))
    deriva = np.interp(np.arange(n), np.linspace(0, n, k), rng.standard_normal(k))
    fase = np.cumsum(f0s * (1 + 0.3 * jitter * deriva)) / TAXA
    idx = np.nonzero(np.diff(np.floor(fase)) > 0)[0] + 1
    idx = np.clip(idx + np.round(rng.standard_normal(len(idx)) * jitter * TAXA / f0s[idx]).astype(int), 0, n - 1)
    amp = np.clip(1 + tremor * rng.standard_normal(len(idx)), 0.1, 2.5)
    amp[1::2] *= 1 - dobra
    x = np.zeros(n)
    np.add.at(x, idx, amp)
    voz = pb(x, tilt, ordem)
    voz /= np.abs(voz).max() + 1e-12
    ar = banda(ruido(n, rng), 300, 9000) * (0.35 + 0.65 * (0.5 + 0.5 * np.cos(2 * np.pi * fase)))
    return voz + np.asarray(sopro) * ar


def ressoa_varia(x, freqs, largura):
    """Ressonância de 2 polos com o centro andando amostra a amostra: o formante que muda quando a boca abre e fecha."""
    n = len(x)
    f = np.broadcast_to(np.asarray(freqs, dtype=float), (n,))
    r = float(np.exp(-np.pi * largura / TAXA))
    a1 = (2 * r * np.cos(2 * np.pi * f / TAXA)).tolist()
    g = ((1 - r) * np.sqrt(1 - 2 * r * np.cos(4 * np.pi * f / TAXA) + r * r)).tolist()   # ganho 1 no pico
    r2 = r * r
    xs = np.asarray(x, dtype=float).tolist()
    y = [0.0] * n
    y1 = y2 = 0.0
    for i in range(n):
        v = g[i] * xs[i] + a1[i] * y1 - r2 * y2
        y[i] = v
        y2, y1 = y1, v
    return np.array(y)


def trato(x, formantes):
    """Garganta, boca e focinho moldando a voz: formantes em paralelo [(freq ou curva de freq, largura_hz, ganho)]."""
    out = np.zeros(len(x))
    for f, bw, g in formantes:
        out += g * (ressoa(x, f, f / bw) if np.isscalar(f) else ressoa_varia(x, f, bw))
    return out


def media_movel(c, w):
    """Média móvel de w amostras, centrada, com as pontas esticadas (soma acumulada: rápida até com janela longa)."""
    if w < 2:
        return np.asarray(c, dtype=float)
    p = np.concatenate([[0.0], np.cumsum(np.pad(np.asarray(c, dtype=float), (w // 2, w - w // 2), mode='edge'))])
    return (p[w:] - p[:-w])[:len(c)] / w


def curva(n, *pontos):
    """Curva suave por pontos [(fração do tempo 0–1, valor)] (contorno de altura, abertura da boca)."""
    u, v = zip(*pontos)
    return media_movel(np.interp(np.linspace(0, 1, n), u, v), int(0.015 * TAXA))


def herbivoro_alarme_a(rng):
    """Herbívoro de manada, alarme (latido): um "bóh" curto, explosivo e rouco, como o latido do cervo — voz de
    ~420 Hz que cai para ~290 Hz, quebrada (sub-harmônico, jitter forte) e cheia de ar, num trato de bicho de porte
    médio (formantes largos a cada ~800 Hz); a boca abre no meio do latido. Ecoa no campo."""
    d = rng.uniform(0.22, 0.26)
    n = int(d * TAXA)
    f0 = curva(n, (0, 400), (0.08, 440), (0.5, 360), (1, 285)) * rng.uniform(0.95, 1.05)
    fonte = glote(rng, f0, 0.035, 0.3, 0.4, curva(n, (0, 0.9), (0.15, 0.45), (1, 0.6)), 1100)
    abre = curva(n, (0, 0.0), (0.25, 1.0), (1, 0.3))
    voz = trato(fonte, [(560 + 240 * abre, 170, 1.0), (1300 + 220 * abre, 220, 0.7), (2350, 280, 0.35),
                        (3300, 350, 0.2), (4300, 420, 0.1)])
    voz *= env(n, 0.005, 0.075, 0.045) * curva(n, (0, 1), (0.7, 1), (1, 0))
    m = int(0.02 * TAXA)                                 # o ar estourando antes da voz pegar
    golpe = trato(banda(ruido(m, rng), 400, 6000) * env(m, 0.001, 0.006), [(700, 300, 1.0), (1500, 350, 0.6), (2500, 400, 0.3)])
    x = pb(junta((golpe, 0.8, 0), (voz, 1.0, 0.003)), 8500, 2)
    return reverb(x, 0.65, 0.22, 4500)


def herbivoro_alarme_b(rng):
    """Herbívoro de manada, alarme (bufo): o ar expulso com força pelas narinas — sopro largo com as ressonâncias do
    focinho, as narinas batendo no começo ("prrf", ~45 por segundo, irregular) e um assobio de ar no meio (ruído
    numa ressonância estreita que cai de ~2,6 para ~2,1 kHz), como o assobio de alarme da camurça."""
    d = rng.uniform(0.38, 0.45)
    n = int(d * TAXA)
    t = tempo(d)
    ar = banda(rosa(n, rng), 250, 8000)
    bate = pb(glote(rng, np.full(n, rng.uniform(40, 50)), 0.12, 0.4, 0.2, 0.0, 300), 300)
    bate = (bate - bate.min()) / (np.ptp(bate) + 1e-12)
    bate = 1 - 0.75 * np.clip(1 - t / 0.18, 0, 1) * (1 - bate)          # a narina para de bater e o ar sai liso
    focinho = trato(ar * bate, [(650, 260, 1.0), (1650, 380, 0.8), (2900, 500, 0.55), (4300, 700, 0.35)]) + 0.15 * banda(ar, 3000, 8000)
    f_ass = curva(n, (0, 2550), (0.3, 2650), (1, 2100)) * rng.uniform(0.95, 1.05)
    assobio = ressoa_varia(ressoa_varia(ar, f_ass, 85), f_ass, 85) * 2.2 * curva(n, (0, 0), (0.15, 0.3), (0.35, 1.0), (0.85, 1.0), (1, 0.4))
    peito = banda(rosa(n, rng), 70, 260) * env(n, 0.006, 0.05)
    x = (focinho * env(n, 0.008, 0.13, 0.05) + 0.8 * assobio * env(n, 0.03, 0.2, 0.08) + 0.6 * peito) * curva(n, (0, 1), (0.8, 1), (1, 0))
    return reverb(pb(x, 9000, 2), 0.6, 0.2, 4500)


def _casco(rng, perto):
    """Um casco batendo na terra: o peso do bicho (baque surdo), o "toc" abafado da unha dura, a terra esmagando e
    torrões soltos; de longe o agudo some."""
    n = int(0.12 * TAXA)
    peso = banda(rosa(n, rng), 75, rng.uniform(200, 280)) * env(n, 0.001, rng.uniform(0.02, 0.03))
    toc = modal(rng, rng.uniform(380, 620), 0.07, rng.uniform(2.5, 4.0), 5, 0.0012, (250, 5000))
    terra = graos(rng, 0.045, int(rng.integers(18, 34)), 350, 3200, 3.0, forma=lambda u: np.exp(-4 * u))
    torrao = graos(rng, 0.08, int(rng.integers(2, 6)), 900, 3500, 4.0, forma=lambda u: 1 - u)
    x = junta((peso, 1.0, 0), (toc, 0.5 * rng.uniform(0.6, 1.0), 0), (terra, 0.9, 0.001), (torrao, 0.35, 0.05))
    return pb(x, 1500 + 7500 * perto, 2)


def _bufo(rng):
    """O ar saindo pelas narinas a cada passada de quem corre."""
    h = int(0.09 * TAXA)
    return trato(banda(rosa(h, rng), 300, 4000), [(650, 300, 1.0), (1700, 450, 0.6)]) * env(h, 0.012, 0.03)


def _empurrao(rng, perto):
    """As patas de trás cavando a terra para o salto: um raspão curto e torrões voando."""
    n = int(0.06 * TAXA)
    raspa = banda(rosa(n, rng), 400, 3500) * env(n, 0.008, 0.02)
    return pb(junta((raspa, 0.6, 0), (graos(rng, 0.1, 12, 600, 3500, 3.0, forma=lambda u: 1 - u), 0.5, 0.01)), 1500 + 7500 * perto, 2)


def _manada(rng, pertos, passadas, pes, forca, bufo_pe, empurra=0.0, L=2.0, k=0.3, pre=0.7):
    """Laço de manada correndo: cada bicho (a distância `perto`, 0 a 1) repete a sua passada — `pes` diz quando cada
    pata toca o chão (s, numa passada de 0,42 s) — com um número inteiro de passadas no laço, então a emenda não
    quebra o ritmo de ninguém. Gera folga antes e depois, para a reverberação e os filtros já entrarem estáveis."""
    n = int((pre + L + k + 0.15) * TAXA)
    x = np.zeros(n)

    def poe(s, tt):
        if -pre <= tt < L + k + 0.05:
            i = int((tt + pre) * TAXA)
            x[i:i + len(s)] += s[:n - i]
    for b, perto in enumerate(pertos):
        m = int(rng.choice(passadas))                    # passadas por laço
        T = L / m
        eps = rng.uniform(-0.05, 0.05, m)
        inicios = rng.uniform(0, T) + np.concatenate([[0.0], np.cumsum(T * (1 + eps - eps.mean()))[:-1]])
        p = np.asarray(pes) * (T / 0.42) ** 0.5 + rng.uniform(-0.006, 0.006, len(pes))
        ganho = 0.05 + 0.95 * perto ** 2.2
        for rep in range(-1, 3):
            for s in inicios:
                for j in range(len(p)):
                    poe(_casco(rng, perto) * forca[j] * rng.uniform(0.7, 1.0) * ganho, rep * L + s + p[j])
                if empurra:
                    poe(_empurrao(rng, perto) * empurra * ganho, rep * L + s + 0.3 * T)
                if b < 2:                                # o bufo de cada passada (só os de perto se ouvem)
                    poe(_bufo(rng) * 0.35 * ganho * rng.uniform(0.6, 1.0), rep * L + s + p[bufo_pe] + 0.03)
    x += banda(rosa(n, rng), 70, 400) * 0.006
    x = reverb(x, 0.55, 0.16, 4000)
    return x[int(pre * TAXA):int((pre + L + k) * TAXA)]


def manada_galope_a(rng):
    """Manada galopando na terra (laço de 2 s), galope: 7 bichos a distâncias diferentes, cada um no galope de 4
    tempos (as duas patas de trás, as duas da frente, o voo; 2, 2,5 ou 3 passadas por segundo) — o "pa-ta-ta-tum"
    rolando; os dois de perto bufam a cada passada."""
    return _manada(rng, (0.95, 0.75, 0.55, 0.45, 0.32, 0.22, 0.14), [4, 5, 5, 6], (0.0, 0.046, 0.139, 0.185),
                   (0.7, 0.65, 1.0, 0.85), 2)


def manada_galope_b(rng):
    """Manada fugindo aos saltos na terra (laço de 2 s), como o cervo-mula e a gazela: 6 bichos, cada salto pousa as
    quatro patas quase juntas (um "tum" pesado, 1,5 a 2 saltos por segundo) e as de trás cavam a terra para o
    próximo; os dois de perto soltam o ar ao pousar."""
    return _manada(rng, (0.9, 0.7, 0.5, 0.35, 0.25, 0.15), [3, 4, 4], (0.0, 0.014, 0.034, 0.044), (0.9, 0.8, 1.0, 0.95), 0,
                   empurra=0.8)


def predador_uivo_a(rng):
    """Predador de matilha, uivo longo e grave (~1,8 s): voz quase limpa que sobe de ~250 para ~350 Hz, fica
    passeando ali e cai no fim, com a boca abrindo ("uuu-aaa-uuu"); um fio de segunda voz aguda, solta da primeira
    (bifonação, como no lobo), aparece no meio. Longe: agudo cortado pelo ar e eco largo de vale."""
    d = rng.uniform(1.7, 1.9)
    n = int(d * TAXA)
    t = tempo(d)
    vaga = np.interp(np.arange(n), np.linspace(0, n, 8), rng.standard_normal(8))
    f0 = curva(n, (0, 250), (0.18, 345), (0.3, 352), (0.75, 360), (0.88, 330), (1, 245)) * (1 + 0.012 * vaga) \
        * (1 + 0.004 * np.sin(2 * np.pi * 4.6 * t)) * rng.uniform(0.94, 1.04)
    fonte = glote(rng, f0, 0.007, 0.06, 0.0, curva(n, (0, 0.25), (0.2, 0.09), (0.85, 0.1), (1, 0.3)), 480, 2)
    abre = curva(n, (0, 0.0), (0.3, 0.9), (0.7, 1.0), (1, 0.15))
    voz = trato(fonte, [(360 + 200 * abre, 130, 1.0), (850 + 300 * abre, 160, 0.5), (2300, 200, 0.18), (3200, 260, 0.08)])
    voz *= curva(n, (0, 0), (0.08, 0.75), (0.2, 1.0), (0.8, 0.95), (1, 0.0)) * (1 + 0.08 * vaga)
    f2 = curva(n, (0, 1750), (0.5, 1880), (1, 1650)) * (1 + 0.01 * vaga)
    segunda = banda(glote(rng, f2, 0.006, 0.08, 0.0, 0.03, 1500, 2), 1400, 2400, 3) * curva(n, (0, 0), (0.38, 0), (0.52, 1), (0.64, 1), (0.78, 0), (1, 0))
    x = pb(voz + 0.035 * segunda, 6000, 2)
    return reverb(x, 1.4, 0.34, 3500)


def predador_uivo_b(rng):
    """Predador de matilha, rosnado de briga (~0,8 s): ronco grave e áspero (~95 Hz, pulsos irregulares e
    sub-harmônico), que sobe num rosnado de boca aberta (~240 Hz, cheio de ar), os dentes estalando duas vezes
    numa mordida e o ronco voltando, cansado."""
    d = rng.uniform(0.78, 0.85)
    n = int(d * TAXA)
    f0 = curva(n, (0, 90), (0.35, 108), (0.45, 225), (0.6, 255), (0.7, 200), (0.78, 120), (1, 95)) * rng.uniform(0.93, 1.07)
    sopro = curva(n, (0, 0.2), (0.4, 0.25), (0.55, 0.55), (0.75, 0.3), (1, 0.25))
    fonte = glote(rng, f0, 0.03, 0.35, 0.45, sopro, 1300)
    abre = curva(n, (0, 0.0), (0.38, 0.1), (0.5, 1.0), (0.68, 0.8), (0.8, 0.15), (1, 0.0))
    voz = trato(fonte, [(460 + 360 * abre, 160, 1.0), (1150 + 450 * abre, 220, 0.6), (2400, 300, 0.3), (3400, 380, 0.15)])
    voz *= curva(n, (0, 0.0), (0.05, 0.45), (0.35, 0.7), (0.5, 1.0), (0.7, 0.85), (0.85, 0.45), (1, 0.0))
    dentes = lambda: junta((modal(rng, rng.uniform(1600, 2200), 0.04, 5, 6, 0.0006, (1000, 9000)), 1.0, 0),
                           (estalo(0.02, rng, 2000, 9000, 0.0015), 0.5, 0))
    at = d * rng.uniform(0.6, 0.66)
    x = junta((voz, 1.0, 0), (dentes(), 0.26, at), (dentes(), 0.19, at + rng.uniform(0.06, 0.08)))
    return reverb(pb(x, 8000, 2), 0.5, 0.15, 5000)


def bolha(rng, f0, d=0.04, sobe=0.6, queda=0.012):
    """Bolha de ar presa na água: a cavidade fecha e o ar "canta" um tom curto que sobe de altura (o "ploc" de quem
    entra na água e o "plim" da gota)."""
    t = tempo(d)
    return osc(f0 * (1 + sobe * t / d), fase=rng.uniform(0, 2 * np.pi)) * env(len(t), 0.0006, queda)


def _gotas(rng, d, quantas, f1=1400, f2=3800, amp=(0.04, 0.12)):
    """Gotas caindo de volta no lago: cada uma um respingo miúdo; só algumas prendem ar e fazem o "plim" (bolha
    pequena, curtíssima)."""
    partes = [(np.zeros(int(d * TAXA)), 1.0, 0)]
    for t0 in np.sort(rng.uniform(0, d, quantas)):
        a = rng.uniform(*amp)
        partes.append((graos(rng, 0.006, 3, 1500, 7000, 2.5, (0.0003, 0.0008)), a * 1.4, t0))
        if rng.uniform() < 0.35:
            partes.append((bolha(rng, rng.uniform(f1, f2), rng.uniform(0.008, 0.014), rng.uniform(0.2, 0.5), rng.uniform(0.002, 0.004)), a * 0.5, t0 + 0.001))
    return junta(*partes)


def peixe_pulo_a(rng):
    """Peixe (~35 cm) pulando no lago, "ploc" limpo: sai da água num "chlup" curto, pinga no ar e entra de cabeça,
    quase sem respingo — o tapa curto na lâmina d'água, a bolha que o corpo arrasta (tom que sobe de ~330 Hz) e
    umas gotas caindo depois."""
    m = int(0.06 * TAXA)
    saida = junta((banda(rosa(m, rng), 400, 3500) * env(m, 0.004, 0.018), 0.5, 0), (bolha(rng, 900, 0.02, 0.4, 0.006), 0.12, 0.004))
    voo = rng.uniform(0.26, 0.31)
    entrada = junta((estalo(0.02, rng, 700, 6000, 0.002), 0.3, 0), (surdo(rng, 0.06, 260, 0.012), 0.45, 0),
                    (bolha(rng, rng.uniform(300, 360), 0.06, 0.9, 0.016), 0.8, 0.006),
                    (bolha(rng, rng.uniform(700, 900), 0.03, 0.6, 0.007), 0.25, 0.013),
                    (graos(rng, 0.05, 40, 900, 6000, 4.0, (0.0003, 0.0012), lambda u: (1 - u) ** 2), 0.6, 0.002))
    n = int(0.2 * TAXA)
    mexe = banda(rosa(n, rng), 200, 1200) * env(n, 0.02, 0.05)          # a água se ajeitando
    return reverb(junta((saida, 1.0, 0), (_gotas(rng, 0.2, 6), 1.0, 0.03), (entrada, 1.0, voo),
                        (_gotas(rng, 0.18, 5, amp=(0.03, 0.08)), 1.0, voo + 0.05), (mexe, 0.1, voo + 0.02)), 0.4, 0.1, 6000)


def peixe_pulo_b(rng):
    """Peixe (~35 cm) pulando no lago, respingo grande: sai da água jogando água, cai de lado num tapa largo e o rabo
    bate de novo logo depois ("tchá-pá"), com o borrifo subindo, várias bolhas graves gorgolejando e a chuva de
    gotas voltando."""
    m = int(0.1 * TAXA)
    saida = junta((banda(rosa(m, rng), 300, 5000) * env(m, 0.003, 0.03), 0.7, 0),
                  (graos(rng, 0.12, 50, 1200, 7000, 4.0, (0.0003, 0.0012), lambda u: (1 - u) ** 1.5), 0.35, 0.01))
    voo = rng.uniform(0.27, 0.32)

    def tapa(g, brilho):
        k = int(0.12 * TAXA)
        return junta((estalo(0.02, rng, 600, 8000 * brilho, 0.004), 1.0 * g, 0), (surdo(rng, 0.08, 300, 0.015), 0.6 * g, 0),
                     (banda(rosa(k, rng), 600, 7000) * env(k, 0.001, 0.04), 0.9 * g, 0.001),
                     (graos(rng, 0.12, 130, 700, 7000, 3.5, (0.0003, 0.0014), lambda u: (1 - u) ** 2), 0.7 * g, 0.003))
    bolhas = junta(*[(bolha(rng, rng.uniform(180, 650), rng.uniform(0.04, 0.08), rng.uniform(0.5, 1.1), rng.uniform(0.012, 0.025)),
                      rng.uniform(0.25, 0.6), rng.uniform(0.005, 0.15)) for _ in range(5)])
    rabo = rng.uniform(0.07, 0.09)
    n = int(0.3 * TAXA)
    mexe = banda(rosa(n, rng), 180, 1100) * env(n, 0.03, 0.1)
    return reverb(junta((saida, 1.0, 0), (_gotas(rng, 0.22, 8), 1.0, 0.03), (tapa(1.0, 0.8), 1.0, voo), (bolhas, 0.8, voo + 0.004),
                        (tapa(0.7, 1.0), 1.0, voo + rabo), (_gotas(rng, 0.3, 14, 1200, 4000, (0.04, 0.14)), 1.0, voo + 0.06),
                        (mexe, 0.18, voo + 0.03)), 0.55, 0.16, 6000)


def _zumbido(rng, t, f0, harm, mexe=0.02):
    """A asa de um mosquito: tom de centenas de Hz com os harmônicos do zumbido fino; a altura treme (a asa nunca
    bate igual) e mexe devagar conforme ele vira no ar."""
    ft = f0 * (1 + mexe * (0.5 * np.sin(2 * np.pi * rng.uniform(0.2, 0.9) * t + rng.uniform(0, 6)) + _passeio(rng, len(t), 4))) \
        * (1 + 0.004 * _passeio(rng, len(t), 40))
    fase = 2 * np.pi * np.cumsum(ft) / TAXA
    return sum(a * np.sin((h + 1) * fase + rng.uniform(0, 2 * np.pi)) for h, a in enumerate(harm))


def _passeio(rng, n, por_s):
    """Curva aleatória suave (−1 a 1, mais ou menos) com `por_s` pontos por segundo: manobra, ida e volta."""
    k = max(4, int(n / TAXA * por_s))
    return media_movel(np.interp(np.arange(n), np.linspace(0, n, k), rng.standard_normal(k)), int(TAXA / por_s * 0.5))


def _harm_mosquito(rng):
    return (1.0, rng.uniform(0.5, 0.9), rng.uniform(0.2, 0.45), rng.uniform(0.1, 0.25), rng.uniform(0.04, 0.12), rng.uniform(0.02, 0.06))


def amb_enxame_a(rng):
    """Nuvem de mosquitos sobre água parada no verão úmido (laço de 3 s), zumbido agudo e cheio: ~70 mosquitos
    (asa de ~500 a ~800 Hz, cada um no seu tom) uns por cima dos outros, a maioria longe e abafada, alguns perto;
    cada um vai e volta devagar. Por baixo, o ar parado da beira do lago."""
    L, k, pre = 3.0, 0.5, 0.6
    d = pre + L + k
    n = int(d * TAXA)
    t = tempo(d)
    perto, meio, longe = np.zeros(n), np.zeros(n), np.zeros(n)
    for m in range(70):
        p = rng.uniform() ** 2
        vai_vem = np.clip(0.6 + 0.45 * _passeio(rng, n, rng.uniform(1.5, 3.5)), 0.15, 1.0)
        s = _zumbido(rng, t, np.exp(rng.normal(np.log(640), 0.12)), _harm_mosquito(rng), 0.035) * vai_vem * (0.06 + 0.94 * p)
        if p > 0.45:
            perto += s
        elif p > 0.12:
            meio += s
        else:
            longe += s
    asas = banda(rosa(n, rng), 500, 6000) * (0.8 + 0.2 * _passeio(rng, n, 3))    # o ar mexido por milhares de asas
    x = pb(perto, 9000, 2) + pb(meio, 4500, 2) + pb(longe, 2200, 2) + asas * 0.25 + banda(rosa(n, rng), 120, 1500) * 0.15
    return reverb(x, 0.5, 0.12, 6000)[int(pre * TAXA):n]


def amb_enxame_b(rng):
    """Enxame sobre água parada (laço de 3 s), mais grave e irregular: ~30 mosquitos grandes (~310 a ~500 Hz) que
    entram e saem da nuvem, a nuvem engrossa e afina, e dois passam perto do ouvido — o tom sobe chegando e cai
    indo embora, o zumbido abre (mais harmônicos) e o volume cresce e some."""
    L, k, pre = 3.0, 0.5, 0.6
    d = pre + L + k
    n = int(d * TAXA)
    t = tempo(d)
    nuvem = np.clip(0.72 + 0.35 * _passeio(rng, n, 2.5), 0.45, 1.0)
    x = np.zeros(n)
    for m in range(30):
        p = rng.uniform() ** 1.3
        some = np.clip(0.55 + 0.9 * _passeio(rng, n, rng.uniform(1.5, 3.5)), 0.08, 1)
        s = _zumbido(rng, t, np.exp(rng.normal(np.log(395), 0.12)), _harm_mosquito(rng), 0.06) * some * (0.08 + 0.92 * p)
        x += pb(s, 1800 + 6000 * p, 2)
    x *= nuvem
    for c, g in ((pre + rng.uniform(1.0, 1.2), 1.0), (pre + rng.uniform(2.25, 2.4), 0.6)):   # cabem inteiros no laço
        u = (t - c) / 0.5
        r = np.sqrt(0.07 ** 2 + (0.55 * u) ** 2)
        amp = (0.07 / r) * np.clip(1.6 - np.abs(u), 0, 1)
        f = rng.uniform(380, 450) * (1 - 0.025 * np.tanh(3 * u))
        voo = _zumbido(rng, t, f, (1.0, 0.8, 0.5, 0.3, 0.18, 0.1, 0.06), 0.01)
        x += pb_varia(voo, 1200 + 9000 * np.clip(amp, 0, 1)) * amp * g * 3.5
    x += banda(rosa(n, rng), 120, 1500) * 0.15
    return reverb(x, 0.5, 0.12, 6000)[int(pre * TAXA):n]


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
    ('sapo', sapo, -17, 0, 0.003), ('amb_moscas', amb_moscas, -26, 0.6, 0),
    ('rato_chiado', rato_chiado, -20, 0, 0.001), ('rato_guincho', rato_guincho, -20, 0, 0.001),
    ('rato_cavar', rato_cavar, -24, 0, 0.001), ('rato_roendo', rato_roendo, -24, 0, 0.002),
    ('filhotes', filhotes, -24, 0, 0.002), ('geado_canto', geado_canto, -24, 0, 0.002),
    ('bando_migrando', bando_migrando, -26, 0, 0.002),
    ('herbivoro_alarme', herbivoro_alarme_a, -18, 0, 0.002), ('herbivoro_alarme_b', herbivoro_alarme_b, -18, 0, 0.004),
    ('manada_galope', manada_galope_a, -19, 0.3, 0), ('manada_galope_b', manada_galope_b, -19, 0.3, 0),
    ('predador_uivo', predador_uivo_a, -20, 0, 0.01), ('predador_rosnado', predador_uivo_b, -17, 0, 0.004),
    ('peixe_pulo_a', peixe_pulo_a, -20, 0, 0.001), ('peixe_pulo', peixe_pulo_b, -19, 0, 0.001),
    ('amb_enxame', amb_enxame_a, -26, 0.5, 0), ('amb_enxame_b', amb_enxame_b, -26, 0.5, 0),
]


## Fase 9: candidatas que não entraram no jogo (escolha pela recomendação; trocar depois se Sapyst preferir).
## Ficam no mesmo lugar da lista (a semente vem da posição) e só saem quando pedidas pelo nome.
GUARDADAS = {'herbivoro_alarme_b', 'manada_galope_b', 'peixe_pulo_a', 'amb_enxame_b'}

VARIACOES = {'aranha_passo': 4, 'pardelo_canto': 3, 'cobrico_canto': 3, 'azulao_canto': 3, 'rubro_canto': 2,
             'planador_grito': 2, 'revoada': 2, 'sapo': 3, 'rato_chiado': 3, 'rato_guincho': 2,
             'filhotes': 2, 'geado_canto': 3, 'bando_migrando': 2}       ## nome → quantos arquivos (nome.wav, nome__2.wav…): o jogo sorteia um a cada vez


if __name__ == '__main__':
    alvos = sys.argv[1:]
    for k, (nome, func, alvo, laco_s, fi) in enumerate(SONS):
        if (alvos and nome not in alvos) or (not alvos and nome in GUARDADAS):
            continue
        fo = 0.25 if nome.startswith(('maq_', 'trem_')) else (0.08 if nome == 'reentrada' else 0.02)
        for v in range(VARIACOES.get(nome, 1)):
            x = finalizar(func(np.random.default_rng(1000 + k + 97 * v)), alvo, laco_s, fi, fo)
            gravar(nome + ('__%d' % (v + 1) if v else ''), x)
        print('SOM %-18s %5.2f s  alvo %5.1f dB%s' % (nome, len(x) / TAXA, alvo, '  (laço)' if laco_s else ''))
