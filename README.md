# EC2 Linux Domain Join Automation

Automação completa para ingresso de instâncias EC2 Linux no Active Directory de forma automática, segura e escalável usando serviços nativos da AWS.

## 📌 Visão Geral

Esta solução detecta automaticamente quando uma nova instância EC2 Linux entra no estado `running` e executa um script via AWS Systems Manager para realizar o ingresso no domínio AD com as configurações corretas.

Tudo isso com:

- ✅ AWS Lambda
- ✅ Amazon EventBridge
- ✅ AWS Systems Manager (SSM)
- ✅ Parameter Store
- ✅ Shell Script customizado
- ✅ Terraform para deploy completo

## 🧠 Como Funciona

1. Uma instância EC2 Linux é iniciada.
2. O EventBridge detecta o evento de mudança de estado para `running`.
3. Uma Lambda é acionada e verifica se a instância é nova e registrada no SSM.
4. A Lambda executa um SSM Document com um script que:
   - Faz o join da instância ao domínio AD
   - Configura DNS dinâmico via SSSD
   - Ajusta o SSH para autenticação via AD
   - Adiciona grupo do domínio como sudoer

## 🖼️ Arquitetura

![Arquitetura da Solução](join.drawio.png)

## ⚙️ Requisitos

### Instância EC2
- Linux com `yum` (Amazon Linux 2, RHEL, CentOS)
- IAM Role com `AmazonSSMManagedInstanceCore`
- Acesso de rede aos Controladores de Domínio
- DNS apontando para o servidor do AD
- Portas abertas: 88, 389, 445, 123, 464

### SSM Parameter Store
Certifique-se de criar os seguintes parâmetros:

| Nome           | Tipo         | Descrição                                 |
|----------------|--------------|-------------------------------------------|
| `DOMAIN`       | String       | Nome FQDN do domínio AD                   |
| `DOMAIN_USER`  | String       | Usuário com permissão de join no domínio  |
| `DOMAIN_PASS`  | SecureString | Senha do usuário AD                       |
| `DOMAIN_GROUP` | String       | Nome do grupo AD com acesso sudo          |

### DHCP Option Set (opcional, mas recomendado)
Configure a VPC para usar um **DHCP Option Set** com o DNS do domínio AD.

---

## ☁️ Deploy com Terraform

1. Clone o repositório
2. Configure os parâmetros no SSM Parameter Store
3. Acesse a pasta `terraform` e execute:

```bash
terraform init
terraform apply
```

---

## 📄 Artigo técnico

Todos os detalhes dessa automação estão descritos no artigo completo:  
📎 *[Insira aqui o link para o Medium]*

---

## 🙋 Sobre o Autor

**Diego Broetto**  
🔗 [linkedin.com/in/diegobroetto](https://www.linkedin.com/in/diegobroetto)  
📧 diego.broetto@darede.com.br
