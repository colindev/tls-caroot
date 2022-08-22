# ref: https://www.golinuxcloud.com/openssl-create-certificate-chain-linux/
# ref: https://www.openssl.org/docs/manmaster/man5/x509v3_config.html

SECRET ?= $(shell openssl rand -base64 32)
KEYLEN ?= 4096
INTERMEDIATE_PATHLEN ?= 3
CAROOT_DAYS ?= 3650
DAYS ?= 365

# step 1: 產生加密密碼檔案
gen-secret-passwd:
	echo $(SECRET) > secret
	openssl enc -aes256 -salt -in secret -out secret.enc
	rm secret

# step 2: 初始化資料夾
init: init-intermediate
	read -p 'organization name?' ORG; echo $$ORG > org
	mkdir -p private certs
	touch index.txt
	echo 01 > serial
	$(MAKE) gen-caroot-config

gen-caroot-config:
	ORG=`cat org` \
	ROOT_DIR=. \
	PATHLEN=$(INTERMEDIATE_PATHLEN) \
		envsubst '$$ROOT_DIR $$ORG $$PATHLEN' < openssl.in \
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

# step 3: 使用加密密碼檔案產生根憑證用的密鑰
gen-caroot-key:
	openssl genrsa -des3 -passout file:secret.enc \
		-out private/cakey.pem \
		$(KEYLEN)

# 驗證根憑證密鑰
verify-caroot-key:
	openssl rsa -noout -text -passin file:secret.enc \
		-in private/cakey.pem 

# step 4: 用根憑證密鑰自簽根憑證
self-sign-caroot-cert:
	openssl req -new -x509 -days $(CAROOT_DAYS) -passin file:secret.enc \
		-config openssl.cnf \
		-extensions v3_ca \
		-key private/cakey.pem \
		-out certs/cacert.pem

# 驗證根憑證
verify-caroot-cert:
	openssl x509 -noout -text -in certs/cacert.pem
	openssl verify -CAfile certs/cacert.pem certs/cacert.pem

# step 5: 使用加密密碼檔案產生中繼憑證用密鑰
gen-intermediate-ca-key:
	openssl genrsa -des3 \
		-passout file:secret.enc \
		-out intermediate/private/cakey.pem \
		$(KEYLEN)

# 驗證中繼憑證密鑰
verify-intermediate-ca-key:
	openssl rsa -noout -text -passin file:secret.enc \
		-in intermediate/private/intermediate.cakey.pem

# step 6: 使用加密密碼檔案並指定sha256算法產生Certificate Signing Request
gen-intermediate-ca-csr:
	openssl req -new -sha256 \
		-passin file:secret.enc \
		-config intermediate/openssl.cnf \
		-key intermediate/private/cakey.pem \
		-out intermediate/csr/req.pem

# step 7: 根憑證商簽署中繼憑證商的CSR
caroot-sign-intermediate-ca-csr:
	openssl ca -notext -days $(DAYS) \
		-passin file:secret.enc \
		-config openssl.cnf \
		-extensions v3_intermediate_ca \
		-in intermediate/csr/req.pem \
		-out intermediate/certs/cacert.pem

verify-intermediate-ca-cert:
	openssl x509 -noout -text \
		-in intermediate/certs/cacert.pem
	openssl verify -CAfile certs/cacert.pem intermediate/certs/cacert.pem

# step 8: 產生憑證鏈
gen-ca-chain-bundle:
	cat intermediate/certs/cacert.pem certs/cacert.pem \
		> intermediate/certs/ca-chain-bundle.pem

# step 9: 產生service key
gen-service-key:
	read -p "service name? " svc; \
	mkdir -p services/$$svc/private; \
	openssl genrsa \
		-out services/$$svc/private/$$svc.key \
		$(KEYLEN)

# step 10: 產生server csr
gen-service-csr:
	read -p "service name? " svc; \
	mkdir -p services/$$svc/csr; \
	openssl req -new -sha256 \
		-key services/$$svc/private/$$svc.key \
		-days $(DAYS) \
		-subj /CN=$$svc \
		-out services/$$svc/csr/req.pem

# step 11: 簽署server cert
intermediate-ca-sign-service-csr:
	read -p "service name? " svc; \
	mkdir -p services/$$svc/certs; \
	openssl x509 -req -sha256 \
		-CA intermediate/certs/ca-chain-bundle.pem \
		-CAkey intermediate/private/cakey.pem \
		-passin file:secret.enc \
		-in services/$$svc/csr/req.pem \
		-out services/$$svc/certs/$$svc.cert \
		-CAcreateserial \
		-days $(DAYS) \
		-extfile server_cert_ext.cnf

verify-service-cert:
	read -p "service name? " svc; \
	openssl x509 -noout -text \
		-in services/$$svc/certs/$$svc.cert; \
	openssl verify -CAfile intermediate/certs/ca-chain-bundle.pem services/$$svc/certs/$$svc.cert

# 清除所有檔案(除了密碼檔)
clear-all:
	read -p 'clear all keys certs? (yes/N):' OK;\
		if [ "$$OK" == "yes" ];\
		then \
			rm -rf org \
				index* \
				serial* \
				openssl.cnf \
				private \
				certs \
				intermediate \
				services \
				;\
		fi
