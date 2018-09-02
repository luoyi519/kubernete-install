# 综述
  
  **必读：本项目是专门针对慕课网的在线课程[《Docker + Kubernetes微服务容器化实践》][5]中的kubernetes实战部分开发部署脚本，源项目请见[ kubernetes-starter ][0]

## [一、预先准备环境][1]
## [二、基础集群部署 - kubernetes-simple][2]
## [三、完整集群部署 - kubernetes-with-ca][3]
## [四、在kubernetes上部署我们的微服务][4]


# 使用方法
## 运行 k8s.sh

# 配置说明
## kubernetes二进制文件目录,eg: /home/michael/bin
   BIN_PATH=/usr/local/bin
   
## 集群定义： 
1) 每行定义分别为 hostname ExtIP PrivateIP username password
2) 第一行代表master节点
3) 例子： 
     DOMAIN=(\
     - S0 138.1.1.1 10.137.48.149 root aaaa
     - S1 165.1.1.1 10.137.48.153 root aaaa\
     )
4) 不设置CERT_MODE缺省为https验证模式，特别地 CERT_MODE=simple 为非验证模式

  [0]: https://github.com/liuyi01/kubernetes-starter
  [1]: https://github.com/luoyi519/kubernete-install/blob/master/docs/1-pre.md
  [2]: https://github.com/luoyi519/kubernete-install/blob/master/docs/2-kubernetes-simple.md
  [3]: https://github.com/luoyi519/kubernete-install/blob/master/docs/3-kubernetes-with-ca.md
  [4]: https://github.com/luoyi519/kubernete-install/blob/master/docs/4-microservice-deploy.md
  [5]: https://coding.imooc.com/class/198.html
