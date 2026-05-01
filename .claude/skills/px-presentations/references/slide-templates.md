# Templates de Slides

Dois conjuntos de templates: **AI Frontiers** (padrao) e **PX Ativos Judiciais** (alternativo).

---

## AI FRONTIERS — Templates

### AF: Cover Slide

```html
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="width: 960px; height: 540px; background: #0b1929; position: relative; margin: 0; font-family: Inter, 'Segoe UI', Arial, sans-serif; overflow: hidden;">
  <!-- Decorative circles -->
  <div style="position: absolute; top: -60px; right: -60px; width: 300px; height: 300px; border-radius: 50%; background: rgba(79,195,247,0.08);"></div>
  <div style="position: absolute; top: -20px; right: -20px; width: 220px; height: 220px; border-radius: 50%; background: rgba(79,195,247,0.12);"></div>
  <div style="position: absolute; top: 20px; right: 20px; width: 140px; height: 140px; border-radius: 50%; background: rgba(79,195,247,0.18);"></div>

  <!-- Logo -->
  <div style="position: absolute; top: 25px; left: 40px;">
    <span style="font-size: 16px; color: #4fc3f7; font-style: italic;">AI</span>
    <span style="font-size: 16px; color: #ffffff; font-weight: 700; text-transform: uppercase;"> FRONTIERS</span>
  </div>

  <!-- Content -->
  <div style="padding: 100px 40px 0 40px;">
    <p style="font-size: 14px; color: #4fc3f7; font-weight: 600; text-transform: uppercase; letter-spacing: 2px; margin: 0 0 10px 0;">PROPOSTA DE</p>
    <h1 style="font-size: 48px; color: #ffffff; font-weight: 700; margin: 0 0 20px 0; line-height: 1.1;">TITULO DA<br>APRESENTACAO</h1>
    <div style="width: 80px; height: 3px; background: #4fc3f7; margin-bottom: 20px;"></div>
    <p style="font-size: 16px; color: rgba(255,255,255,0.8); margin: 0; max-width: 500px; line-height: 1.5;">Subtitulo descritivo da apresentacao com mais detalhes sobre o conteudo</p>
  </div>

  <!-- Info boxes -->
  <div style="position: absolute; bottom: 50px; left: 40px; right: 40px; display: flex; gap: 20px;">
    <div style="flex: 1; background: #162338; border-radius: 8px; padding: 16px 20px;">
      <p style="font-size: 10px; color: #4fc3f7; font-weight: 700; text-transform: uppercase; letter-spacing: 1px; margin: 0 0 6px 0;">PARA</p>
      <p style="font-size: 14px; color: #ffffff; font-weight: 600; margin: 0;">Nome do Cliente</p>
    </div>
    <div style="flex: 1; background: #162338; border-radius: 8px; padding: 16px 20px;">
      <p style="font-size: 10px; color: #4fc3f7; font-weight: 700; text-transform: uppercase; letter-spacing: 1px; margin: 0 0 6px 0;">DATA</p>
      <p style="font-size: 14px; color: #ffffff; font-weight: 600; margin: 0;">04 de fevereiro de 2026</p>
    </div>
    <div style="flex: 1; background: #162338; border-radius: 8px; padding: 16px 20px;">
      <p style="font-size: 10px; color: #4fc3f7; font-weight: 700; text-transform: uppercase; letter-spacing: 1px; margin: 0 0 6px 0;">PROPOSTA</p>
      <p style="font-size: 14px; color: #ffffff; font-weight: 600; margin: 0;">AI-FR-PC-2026-001</p>
    </div>
  </div>
</body>
</html>
```

### AF: Content Slide (Light + Metrics)

```html
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="width: 960px; height: 540px; background: #ffffff; position: relative; margin: 0; font-family: Inter, 'Segoe UI', Arial, sans-serif;">
  <!-- Title -->
  <div style="padding: 30px 40px 15px 40px;">
    <h1 style="font-size: 30px; color: #1e293b; font-weight: 700; margin: 0;">Titulo da Secao</h1>
    <p style="font-size: 13px; color: #6b7280; margin: 6px 0 0 0;">Subtitulo descritivo da secao</p>
  </div>

  <!-- Callout -->
  <div style="margin: 0 40px 20px 40px; border-left: 4px solid #4fc3f7; background: #f8fafc; padding: 16px 20px; border-radius: 0 8px 8px 0;">
    <p style="font-size: 13px; color: #1e293b; margin: 0; line-height: 1.6;">Texto de destaque ou descricao principal que merece atencao especial do leitor.</p>
  </div>

  <!-- Metric cards row (2 navy + 2 cyan) -->
  <div style="display: flex; gap: 20px; padding: 0 40px; margin-bottom: 20px;">
    <div style="flex: 1; background: #1e3a5f; border-radius: 8px; padding: 20px; text-align: center;">
      <p style="font-size: 42px; color: #ffffff; font-weight: 700; margin: 0;">5</p>
      <p style="font-size: 11px; color: #ffffff; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; margin: 5px 0 0 0;">SEMANAS</p>
    </div>
    <div style="flex: 1; background: #1e3a5f; border-radius: 8px; padding: 20px; text-align: center;">
      <p style="font-size: 42px; color: #ffffff; font-weight: 700; margin: 0;">20h</p>
      <p style="font-size: 11px; color: #ffffff; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; margin: 5px 0 0 0;">DE MENTORIA</p>
    </div>
    <div style="flex: 1; background: #5bbad5; border-radius: 8px; padding: 20px; text-align: center;">
      <p style="font-size: 42px; color: #ffffff; font-weight: 700; margin: 0;">70%</p>
      <p style="font-size: 11px; color: #ffffff; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; margin: 5px 0 0 0;">PRATICO</p>
    </div>
    <div style="flex: 1; background: #5bbad5; border-radius: 8px; padding: 20px; text-align: center;">
      <p style="font-size: 42px; color: #ffffff; font-weight: 700; margin: 0;">+2h</p>
      <p style="font-size: 11px; color: #ffffff; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; margin: 5px 0 0 0;">BONUS ADVISORY</p>
    </div>
  </div>

  <!-- Bullets with arrows -->
  <div style="padding: 0 40px;">
    <p style="font-size: 14px; color: #1e293b; font-weight: 700; margin: 0 0 10px 0;">Escopo: Titulo</p>
    <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 6px;">
      <span style="color: #4fc3f7; font-size: 14px;">&#10132;</span>
      <span style="font-size: 12px; color: #1e293b;">Item de escopo um</span>
    </div>
    <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 6px;">
      <span style="color: #4fc3f7; font-size: 14px;">&#10132;</span>
      <span style="font-size: 12px; color: #1e293b;">Item de escopo dois</span>
    </div>
  </div>

  <!-- Footer -->
  <div style="position: absolute; bottom: 0; left: 0; right: 0; height: 32px; background: #1e3a5f; display: flex; align-items: center; justify-content: space-between; padding: 0 40px;">
    <p style="font-size: 9px; color: rgba(255,255,255,0.7); margin: 0;">AI Frontiers | Proposta Comercial</p>
    <p style="font-size: 9px; color: #4fc3f7; margin: 0;">03</p>
  </div>
</body>
</html>
```

### AF: Scope Slide (2 Colunas com Cards)

```html
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="width: 960px; height: 540px; background: #ffffff; position: relative; margin: 0; font-family: Inter, 'Segoe UI', Arial, sans-serif;">
  <!-- Title -->
  <div style="padding: 30px 40px 5px 40px;">
    <h1 style="font-size: 30px; color: #1e293b; font-weight: 700; margin: 0;">Escopo — Semanas 1 e 2</h1>
    <p style="font-size: 13px; color: #6b7280; margin: 6px 0 0 0;">4 horas por semana &bull; Total: 8 horas</p>
  </div>

  <!-- Two column cards -->
  <div style="display: flex; gap: 25px; padding: 20px 40px 0 40px;">
    <!-- Card Left (Navy header) -->
    <div style="flex: 1; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">
      <div style="background: #1e3a5f; padding: 14px 20px; display: flex; align-items: center; gap: 10px;">
        <span style="font-size: 18px;">&#129504;</span>
        <span style="font-size: 15px; color: #ffffff; font-weight: 700;">Context-Driven Design & DDD</span>
      </div>
      <div style="background: #ffffff; padding: 16px 20px;">
        <div style="display: flex; align-items: flex-start; gap: 8px; margin-bottom: 10px;">
          <span style="color: #22c55e; font-size: 14px;">&#10004;</span>
          <span style="font-size: 12px; color: #1e293b;">Metodologia de desenvolvimento dirigido por contexto</span>
        </div>
        <div style="display: flex; align-items: flex-start; gap: 8px; margin-bottom: 10px;">
          <span style="color: #22c55e; font-size: 14px;">&#10004;</span>
          <span style="font-size: 12px; color: #1e293b;">Tecnicas de prompt engineering para codigo</span>
        </div>
        <div style="display: flex; align-items: flex-start; gap: 8px; margin-bottom: 10px;">
          <span style="color: #22c55e; font-size: 14px;">&#10004;</span>
          <span style="font-size: 12px; color: #1e293b;">Documentacao como combustivel da IA</span>
        </div>
        <div style="display: flex; align-items: flex-start; gap: 8px;">
          <span style="color: #22c55e; font-size: 14px;">&#10004;</span>
          <span style="font-size: 12px; color: #1e293b;">Setup completo do Claude Code</span>
        </div>
      </div>
    </div>

    <!-- Card Right (Cyan header) -->
    <div style="flex: 1; border-radius: 12px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">
      <div style="background: #5bbad5; padding: 14px 20px; display: flex; align-items: center; gap: 10px;">
        <span style="font-size: 18px;">&#128187;</span>
        <span style="font-size: 15px; color: #ffffff; font-weight: 700;">Documentacao e Contexto</span>
      </div>
      <div style="background: #ffffff; padding: 16px 20px;">
        <div style="display: flex; align-items: flex-start; gap: 8px; margin-bottom: 10px;">
          <span style="color: #22c55e; font-size: 14px;">&#10004;</span>
          <span style="font-size: 12px; color: #1e293b;">Criacao do Contexto para o projeto</span>
        </div>
        <div style="display: flex; align-items: flex-start; gap: 8px; margin-bottom: 10px;">
          <span style="color: #22c55e; font-size: 14px;">&#10004;</span>
          <span style="font-size: 12px; color: #1e293b;">Prototipagem rapida do sistema</span>
        </div>
        <div style="display: flex; align-items: flex-start; gap: 8px; margin-bottom: 10px;">
          <span style="color: #22c55e; font-size: 14px;">&#10004;</span>
          <span style="font-size: 12px; color: #1e293b;">Validacao de conceitos (POCs)</span>
        </div>
        <div style="display: flex; align-items: flex-start; gap: 8px;">
          <span style="color: #22c55e; font-size: 14px;">&#10004;</span>
          <span style="font-size: 12px; color: #1e293b;">Hands-on pratico com projetos reais</span>
        </div>
      </div>
    </div>
  </div>

  <!-- Footer -->
  <div style="position: absolute; bottom: 0; left: 0; right: 0; height: 32px; background: #1e3a5f; display: flex; align-items: center; justify-content: space-between; padding: 0 40px;">
    <p style="font-size: 9px; color: rgba(255,255,255,0.7); margin: 0;">AI Frontiers | Proposta Comercial</p>
    <p style="font-size: 9px; color: #4fc3f7; margin: 0;">04</p>
  </div>
</body>
</html>
```

### AF: Results Slide (Dark + Metrics)

```html
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="width: 960px; height: 540px; background: #0b1929; position: relative; margin: 0; font-family: Inter, 'Segoe UI', Arial, sans-serif;">
  <!-- Title -->
  <div style="padding: 30px 40px 10px 40px;">
    <h1 style="font-size: 30px; color: #ffffff; font-weight: 700; margin: 0;">Resultados Esperados</h1>
    <p style="font-size: 13px; color: #94a3b8; margin: 6px 0 0 0;">Ao final da mentoria, a equipe estara capacitada para:</p>
  </div>

  <!-- 4 metric cards on dark -->
  <div style="display: flex; gap: 20px; padding: 20px 40px;">
    <div style="flex: 1; background: #162338; border: 1px solid rgba(79,195,247,0.2); border-radius: 8px; padding: 20px; text-align: center;">
      <div style="width: 48px; height: 48px; border-radius: 50%; background: #1a2940; margin: 0 auto 12px; display: flex; align-items: center; justify-content: center;">
        <span style="font-size: 22px;">&#128640;</span>
      </div>
      <p style="font-size: 36px; color: #4fc3f7; font-weight: 700; margin: 0;">10x</p>
      <p style="font-size: 13px; color: #ffffff; font-weight: 700; margin: 6px 0 4px 0;">Mais rapido</p>
      <p style="font-size: 11px; color: #94a3b8; margin: 0;">Desenvolver com ferramentas de IA</p>
    </div>
    <div style="flex: 1; background: #162338; border: 1px solid rgba(79,195,247,0.2); border-radius: 8px; padding: 20px; text-align: center;">
      <div style="width: 48px; height: 48px; border-radius: 50%; background: #1a2940; margin: 0 auto 12px; display: flex; align-items: center; justify-content: center;">
        <span style="font-size: 22px;">&#9201;</span>
      </div>
      <p style="font-size: 36px; color: #4fc3f7; font-weight: 700; margin: 0;">Dias</p>
      <p style="font-size: 13px; color: #ffffff; font-weight: 700; margin: 6px 0 4px 0;">Nao meses</p>
      <p style="font-size: 11px; color: #94a3b8; margin: 0;">Criar features em tempo recorde</p>
    </div>
    <div style="flex: 1; background: #162338; border: 1px solid rgba(79,195,247,0.2); border-radius: 8px; padding: 20px; text-align: center;">
      <div style="width: 48px; height: 48px; border-radius: 50%; background: #1a2940; margin: 0 auto 12px; display: flex; align-items: center; justify-content: center;">
        <span style="font-size: 22px;">&#128196;</span>
      </div>
      <p style="font-size: 36px; color: #4fc3f7; font-weight: 700; margin: 0;">100%</p>
      <p style="font-size: 13px; color: #ffffff; font-weight: 700; margin: 6px 0 4px 0;">Documentado</p>
      <p style="font-size: 11px; color: #94a3b8; margin: 0;">Projetos completamente documentados</p>
    </div>
    <div style="flex: 1; background: #162338; border: 1px solid rgba(79,195,247,0.2); border-radius: 8px; padding: 20px; text-align: center;">
      <div style="width: 48px; height: 48px; border-radius: 50%; background: #1a2940; margin: 0 auto 12px; display: flex; align-items: center; justify-content: center;">
        <span style="font-size: 22px;">&#129504;</span>
      </div>
      <p style="font-size: 36px; color: #4fc3f7; font-weight: 700; margin: 0;">Total</p>
      <p style="font-size: 13px; color: #ffffff; font-weight: 700; margin: 6px 0 4px 0;">Autonomia</p>
      <p style="font-size: 11px; color: #94a3b8; margin: 0;">Planejar projetos de automacao</p>
    </div>
  </div>

  <!-- Banner -->
  <div style="margin: 15px 40px; background: rgba(79,195,247,0.12); border-radius: 8px; padding: 14px 24px; text-align: center;">
    <p style="font-size: 14px; color: #ffffff; font-weight: 600; margin: 0;">Transforme sua equipe de desenvolvimento em um super time acelerado por IA</p>
  </div>

  <!-- Footer -->
  <div style="position: absolute; bottom: 0; left: 0; right: 0; height: 32px; background: #162338; display: flex; align-items: center; justify-content: space-between; padding: 0 40px;">
    <p style="font-size: 9px; color: #94a3b8; margin: 0;">AI Frontiers | Proposta Comercial</p>
    <p style="font-size: 9px; color: #4fc3f7; margin: 0;">08</p>
  </div>
</body>
</html>
```

### AF: Closing Slide

```html
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="width: 960px; height: 540px; background: #0b1929; position: relative; margin: 0; font-family: Inter, 'Segoe UI', Arial, sans-serif; overflow: hidden;">
  <!-- Decorative circles -->
  <div style="position: absolute; top: -60px; right: -60px; width: 300px; height: 300px; border-radius: 50%; background: rgba(79,195,247,0.08);"></div>
  <div style="position: absolute; top: -20px; right: -20px; width: 220px; height: 220px; border-radius: 50%; background: rgba(79,195,247,0.12);"></div>
  <div style="position: absolute; top: 20px; right: 20px; width: 140px; height: 140px; border-radius: 50%; background: rgba(79,195,247,0.18);"></div>

  <!-- Logo -->
  <div style="position: absolute; top: 25px; left: 40px;">
    <span style="font-size: 16px; color: #4fc3f7; font-style: italic;">AI</span>
    <span style="font-size: 16px; color: #ffffff; font-weight: 700; text-transform: uppercase;"> FRONTIERS</span>
  </div>

  <!-- Title -->
  <div style="padding: 70px 40px 0 40px;">
    <h1 style="font-size: 44px; color: #ffffff; font-weight: 700; margin: 0;">Vamos Comecar?</h1>
  </div>

  <!-- Step cards -->
  <div style="display: flex; gap: 20px; padding: 25px 40px 0 40px;">
    <div style="flex: 1; background: #162338; border-radius: 8px; padding: 20px;">
      <p style="font-size: 28px; color: #4fc3f7; font-weight: 700; margin: 0 0 8px 0;">01</p>
      <p style="font-size: 15px; color: #ffffff; font-weight: 700; margin: 0 0 4px 0;">Aprovacao da Proposta</p>
      <p style="font-size: 11px; color: #94a3b8; margin: 0;">Confirmacao e formalizacao</p>
    </div>
    <div style="flex: 1; background: #162338; border-radius: 8px; padding: 20px;">
      <p style="font-size: 28px; color: #4fc3f7; font-weight: 700; margin: 0 0 8px 0;">02</p>
      <p style="font-size: 15px; color: #ffffff; font-weight: 700; margin: 0 0 4px 0;">Kick-off</p>
      <p style="font-size: 11px; color: #94a3b8; margin: 0;">Alinhamento inicial com a equipe</p>
    </div>
    <div style="flex: 1; background: #162338; border-radius: 8px; padding: 20px;">
      <p style="font-size: 28px; color: #4fc3f7; font-weight: 700; margin: 0 0 8px 0;">03</p>
      <p style="font-size: 15px; color: #ffffff; font-weight: 700; margin: 0 0 4px 0;">Primeira Sessao</p>
      <p style="font-size: 11px; color: #94a3b8; margin: 0;">Configuracao do ambiente</p>
    </div>
  </div>

  <!-- Separator -->
  <div style="margin: 25px 40px; width: 80px; height: 3px; background: #4fc3f7;"></div>

  <!-- Contact section -->
  <div style="display: flex; justify-content: space-between; padding: 0 40px; align-items: flex-end;">
    <div>
      <p style="font-size: 10px; color: #4fc3f7; font-weight: 700; text-transform: uppercase; letter-spacing: 1px; margin: 0 0 6px 0;">CONTATO</p>
      <p style="font-size: 18px; color: #ffffff; font-weight: 700; margin: 0;">Rafael Fiales</p>
      <p style="font-size: 12px; color: #94a3b8; margin: 4px 0 0 0;">Chief AI Officer & Mentor Especialista IA</p>
    </div>
    <div style="text-align: right;">
      <p style="font-size: 12px; color: #4fc3f7; margin: 0 0 4px 0; text-decoration: underline;">rafaelcortezfiales@gmail.com</p>
      <p style="font-size: 12px; color: #4fc3f7; margin: 0 0 4px 0;">linkedin.com/in/rafael-fiales</p>
      <p style="font-size: 12px; color: #4fc3f7; margin: 0;">(11) 91866-2935</p>
    </div>
  </div>

  <!-- Validity note -->
  <div style="position: absolute; bottom: 40px; left: 0; right: 0; text-align: center;">
    <p style="font-size: 11px; color: #64748b; font-style: italic; margin: 0;">Proposta valida por 15 dias</p>
  </div>

  <!-- Footer -->
  <div style="position: absolute; bottom: 0; left: 0; right: 0; height: 32px; background: #162338; display: flex; align-items: center; justify-content: space-between; padding: 0 40px;">
    <p style="font-size: 9px; color: #94a3b8; margin: 0;">AI Frontiers | Proposta Comercial</p>
    <p style="font-size: 9px; color: #4fc3f7; margin: 0;">10</p>
  </div>
</body>
</html>
```

---

## PX ATIVOS JUDICIAIS — Templates (Alternativo)

### PX: Cover Slide

```html
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="width: 960px; height: 540px; background: linear-gradient(135deg, #1e3a5f 0%, #2d4a6f 100%); position: relative; margin: 0; font-family: Arial, sans-serif;">
  <!-- Accent bar -->
  <div style="position: absolute; top: 0; right: 80px; width: 60px; height: 100px; background: #f0a500; border-radius: 0 0 8px 8px;"></div>

  <!-- Content -->
  <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; padding: 60px;">
    <h1 style="font-size: 72px; color: #ffffff; font-weight: 700; letter-spacing: 2px; margin: 0;">TITULO</h1>
    <p style="font-size: 120px; color: #f0a500; font-weight: 800; margin: -10px 0 30px 0; letter-spacing: 4px;">2026</p>
    <div style="width: 120px; height: 4px; background: #f0a500; margin-bottom: 30px;"></div>
    <p style="font-size: 18px; color: rgba(255,255,255,0.8); letter-spacing: 1px;">PX ATIVOS JUDICIAIS</p>
  </div>
</body>
</html>
```

### PX: Content Slide

```html
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="width: 960px; height: 540px; background: #ffffff; position: relative; margin: 0; font-family: Arial, sans-serif;">
  <!-- Header bar -->
  <div style="width: 100%; height: 60px; background: #1e3a5f; position: relative;">
    <div style="position: absolute; top: 0; right: 80px; width: 50px; height: 80px; background: #f0a500; border-radius: 0 0 6px 6px;"></div>
  </div>

  <!-- Title -->
  <div style="padding: 30px 40px 20px 40px;">
    <h1 style="font-size: 32px; color: #1e3a5f; margin: 0;">Titulo da <span style="color: #f0a500;">Secao</span></h1>
    <p style="font-size: 14px; color: #666; margin: 8px 0 0 0;">Subtitulo descritivo</p>
  </div>

  <!-- Metrics row -->
  <div style="display: flex; gap: 20px; padding: 15px 40px;">
    <div style="flex: 1; background: #1e3a5f; padding: 25px 20px; border-radius: 8px; text-align: center;">
      <p style="font-size: 48px; color: #ffffff; font-weight: 700; margin: 0;">500+</p>
      <p style="font-size: 13px; color: rgba(255,255,255,0.8); margin: 5px 0 0 0;">Label</p>
    </div>
    <div style="flex: 1; background: #f0a500; padding: 25px 20px; border-radius: 8px; text-align: center;">
      <p style="font-size: 48px; color: #1e3a5f; font-weight: 700; margin: 0;">200+</p>
      <p style="font-size: 13px; color: rgba(30,58,95,0.8); margin: 5px 0 0 0;">Label</p>
    </div>
    <div style="flex: 1; background: #f5f7fa; padding: 25px 20px; border-radius: 8px; border: 1px solid #e2e8f0; text-align: center;">
      <p style="font-size: 48px; color: #1e3a5f; font-weight: 700; margin: 0;">100%</p>
      <p style="font-size: 13px; color: #666; margin: 5px 0 0 0;">Label</p>
    </div>
  </div>

  <!-- Footer -->
  <div style="position: absolute; bottom: 25px; left: 40px;">
    <p style="font-size: 10px; color: #999; margin: 0;">Tech Report 2026 | PX Ativos Judiciais</p>
  </div>
  <div style="position: absolute; bottom: 25px; right: 40px;">
    <p style="font-size: 10px; color: #999; margin: 0;">01</p>
  </div>
</body>
</html>
```

### PX: Closing Slide

```html
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"></head>
<body style="width: 960px; height: 540px; background: linear-gradient(135deg, #1e3a5f 0%, #2d4a6f 100%); position: relative; margin: 0; font-family: Arial, sans-serif;">
  <!-- Accent bar -->
  <div style="position: absolute; top: 0; right: 80px; width: 60px; height: 100px; background: #f0a500; border-radius: 0 0 8px 8px;"></div>

  <!-- Content -->
  <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; padding: 60px;">
    <h1 style="font-size: 64px; color: #ffffff; font-weight: 700; margin: 0 0 30px 0;">Obrigado!</h1>

    <!-- Metrics -->
    <div style="display: flex; gap: 50px; margin-bottom: 40px;">
      <div style="text-align: center;">
        <p style="font-size: 48px; color: #f0a500; font-weight: 700; margin: 0;">15+</p>
        <p style="font-size: 12px; color: rgba(255,255,255,0.7); margin: 5px 0 0 0;">Metrica 1</p>
      </div>
      <div style="text-align: center;">
        <p style="font-size: 48px; color: #f0a500; font-weight: 700; margin: 0;">8</p>
        <p style="font-size: 12px; color: rgba(255,255,255,0.7); margin: 5px 0 0 0;">Metrica 2</p>
      </div>
      <div style="text-align: center;">
        <p style="font-size: 48px; color: #f0a500; font-weight: 700; margin: 0;">100%</p>
        <p style="font-size: 12px; color: rgba(255,255,255,0.7); margin: 5px 0 0 0;">Metrica 3</p>
      </div>
    </div>

    <div style="width: 120px; height: 4px; background: #f0a500; margin-bottom: 25px;"></div>
    <p style="font-size: 14px; color: rgba(255,255,255,0.8); text-align: center; max-width: 600px; line-height: 1.6; margin: 0;">Mensagem de encerramento com visao de futuro.</p>
  </div>

  <!-- Footer -->
  <div style="position: absolute; bottom: 25px; left: 0; right: 0; text-align: center;">
    <p style="font-size: 12px; color: rgba(255,255,255,0.5); margin: 0;">PX ATIVOS JUDICIAIS | 2026</p>
  </div>
</body>
</html>
```

---

## Mapeamento de Cores pptxgenjs

Ao usar pptxgenjs diretamente (sem HTML), use estes objetos de cores:

### AI Frontiers Colors (pptxgenjs)
```javascript
const AF = {
  bgDarkest:    '0b1929',    // Cover/closing bg
  bgDark:       '0d1f33',    // Alt dark bg
  bgSurface:    '162338',    // Cards on dark, footer dark
  bgHover:      '1a2940',    // Icon circles, hover states
  navy:         '1e3a5f',    // Headers, navy cards, footer light
  navyDark:     '163050',    // Darker navy variant
  accent:       '4fc3f7',    // Cyan: labels, numbers, links, separators
  accentLight:  '81d4fa',    // Light cyan variant
  secondary:    '5bbad5',    // Blue: alt cards, scope card headers
  white:        'FFFFFF',
  textDark:     '1e293b',    // Text on light bg
  textSubtitle: '6b7280',    // Subtitles on light
  textSecondary:'94a3b8',    // Text on dark bg (secondary)
  textMuted:    '64748b',    // Muted text
  success:      '22c55e',    // Green checkmarks
  borderLight:  'e2e8f0',    // Borders on light
  borderDark:   '2a3f5f',    // Approx rgba(79,195,247,0.2)
  circleOuter:  'rgba(79,195,247,0.08)',
  circleMiddle: 'rgba(79,195,247,0.12)',
  circleInner:  'rgba(79,195,247,0.18)',
  bannerBg:     'rgba(79,195,247,0.12)'
};
```

### PX Colors (pptxgenjs)
```javascript
const PX = {
  navy:       '1e3a5f',
  navyDark:   '2d4a6f',
  amber:      'f0a500',
  white:      'FFFFFF',
  gray:       '666666',
  lightGray:  '999999',
  muted:      'f5f7fa',
  green:      '7ac47a',
  border:     'e2e8f0'
};
```
