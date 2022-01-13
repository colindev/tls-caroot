# reference: https://www.golinuxcloud.com/openssl-create-certificate-chain-linux/

SECRET ?= $(shell openssl rand -base64 32)
KEYLEN ?= 4096
INTERMEDIATE_PATHLEN ?= 3
CAROOT_DAYS ?= 3650
DAYS ?= 365

# 產生加密密碼檔案
gen-secret-passwd:
	echo $(SECRET) > secret
	openssl enc -aes256 -salt -in secret -out secret.enc
	rm secret

# 初始化資料夾
init: init-intermediate
	read -p 'organization name?' ORG; echo $$ORG > org
	mkdir -p private certs
	touch index.txt
	echo 01 > serial
	$(MAKE) gen-caroot-config

gen-caroot-config:
	ORG=`cat org` \
	ROOT_DIR=. \
		envsubst '$$ROOT_DIR $$ORG' < openssl.in \
		> openssl.cnf

# 初始化中繼CA資料夾
init-intermediate:
	mkdir -p intermediate/{private,certs,csr}
	touch intermediate/index.txt
	echo 01 > intermediate/serial
	echo 01 > intermediate/crlnumber
	$(MAKE) gen-intermediate-config

gen-intermediate-config:
	ORG=`cat org` \
	ROOT_DIR=intermediate \
	PATHLEN=$(INTERMEDIATE_PATHLEN) \
		envsubst '$$ROOT_DIR $$ORG $$PATHLEN' < openssl.in \
		> intermediate/openssl.cnf

# 使用加密密碼檔案產生根憑證用的密鑰
gen-caroot-key:
	openssl genrsa -des3 -passout file:secret.enc \
		-out private/cakey.pem \
		$(KEYLEN)

# 驗證根憑證密鑰
verify-caroot-key:
	openssl rsa -noout -text -passin file:secret.enc \
		-in private/cakey.pem 

# 用根憑證密鑰自簽根憑證
self-sign-caroot-cert:
	openssl req -new -x509 -days $(CAROOT_DAYS) -passin file:secret.enc \
		-config openssl.cnf \
		-extensions v3_ca \
		-key private/cakey.pem \
		-out certs/cacert.pem

# 驗證根憑證
verify-caroot-cert:
	openssl x509 -noout -text -in certs/cacert.pem

# 使用加密密碼檔案產生中繼憑證用密鑰
gen-intermediate-ca-key:
	openssl genrsa -des3 -passout file:secret.enc \
		-out intermediate/private/intermediate.cakey.pem \
		$(KEYLEN)

# 驗證中繼憑證密鑰
verify-intermediate-ca-key:
	openssl rsa -noout -text -passin file:secret.enc \
		-in intermediate/private/intermediate.cakey.pem

# 使用加密密碼檔案並指定sha256算法產生Certificate Signing Request
gen-intermediate-ca-csr:
	openssl req -new -sha256 -passin file:secret.enc \
		-config intermediate/openssl.cnf \
		-key intermediate/private/intermediate.cakey.pem \
		-out intermediate/csr/intermediate.csr.pem

# 根憑證商簽署中繼憑證商的CSR
caroot-sign-intermediate-ca-csr:
	openssl ca -notext -days $(DAYS) -passin file:secret.enc \
		-config openssl.cnf \
		-extensions v3_intermediate_ca \
		-in intermediate/csr/intermediate.csr.pem \
		-out intermediate/certs/intermediate.cacert.pem

verify-intermediate-ca-cert:
	openssl x509 -noout -text \
		-in intermediate/certs/intermediate.cacert.pem

caroot-verify-intermediate-ca-cert:
	openssl verify -CAfile certs/cacert.pem intermediate/certs/intermediate.cacert.pem

# 清除所有檔案(除了密碼檔)
clear-all:
	read -p 'clear all keys certs? (yes/N):' OK;\
		if [ "$$OK" == "yes" ];\
		then \
			rm -f org \
				index* \
				serial* \
				openssl.cnf \
				private/* \
				certs/* \
				intermediate/{index,serial}* \
				intermediate/openssl.cnf \
				intermediate/crlnumber \
				intermediate/{private,certs,csr}/* \
				;\
		fi
