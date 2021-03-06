import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:movelo/Api/apiResponse.dart';
import 'package:movelo/models/arbol.dart';
import 'package:movelo/models/biciusuario.dart';
import 'package:movelo/models/registroGeografico.dart';
import 'package:movelo/models/user.dart';
import 'package:movelo/providers/estadoGlobal.dart';
import 'package:movelo/resources/respositoryAll.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

class Bloc {
  final _repository = RepositoryAll();
  final _arbolesUsuarioFetcher = PublishSubject<ApiResponse<ArbolModel>>();
  final _todosArbolesFetcher = PublishSubject<ApiResponse<ArbolModel>>();

  Future iniciarSesion(
      String correo, String contrasena, BuildContext context) async {
    var myProvider = Provider.of<EstadoGlobal>(context, listen: false);
    var respuesta = false;
    User resp = await this.verificaUsuario(correo, contrasena);
    if (resp != null) {
      if (resp is Biciusuario) {
        Biciusuario biciuser = resp;
        myProvider.biciusuarioUser = biciuser;
        myProvider.tipo = "Biciusuario";
        respuesta = true;
      }
    } else {
      respuesta = false;
    }
    return respuesta;
  }

  Future registrarUsuario(Biciusuario biciusuario, BuildContext context) async {
    var myProvider = Provider.of<EstadoGlobal>(context, listen: false);
    var respuesta = false;
    bool resp = await this._repository.insertBiciusuario(biciusuario);
    if (resp != null) {
      Biciusuario biciuser = biciusuario;
      myProvider.biciusuarioUser = biciuser;
      myProvider.tipo = "Biciusuario";
      respuesta = true;
    } else {
      respuesta = false;
    }
    return respuesta;
  }

  Future<bool> enviarKmRecorridos(double km) async {
    bool respuesta = await this._repository.enviarKmRecorridos(km);
    return respuesta;
  }

  Future<bool> enviarRegistroRuta(
      List<Registro> registros, double distancia, String correo) async {
    bool respuesta =
        await this._repository.enviarRegistroRuta(registros, distancia, correo);
    return respuesta;
  }

  //Usuario
  Future verificaUsuario(String mail, password) async {
    var user;
    try {
      user = await _repository.iniciarSesion(mail,
          password); // El código es muy parecido, sólo cambian las entidades
    } on Exception {}
    return user;
  }

  Future getUsuarioCorreo(String correo) async {
    var user;
    try {
      user = await _repository.obtenerUsuarioCorreo(
          correo); // El código es muy parecido, sólo cambian las entidades
    } on Exception {
      throw Exception();
    }
    return user;
  }

  Future<bool> anadirArbolUser(String correo, double precio) async {
    var resp;
    try {
      resp = await _repository.anadirArbolUser(correo, precio);
    } on Exception {
      throw Exception();
    }
    return resp;
  }

  //Arboles
  obtenerTodosArboles(BuildContext context) async {
    try {
      ArbolModel arbol = await _repository.obtenerTodosArboles();
      _todosArbolesFetcher.sink.add(ApiResponse.completed(arbol));
    } on Exception {
      _todosArbolesFetcher.sink.add(ApiResponse.error());
    }
  }

  obtenerArbolesUser(String correo) async {
    try {
      ArbolModel arbol = await _repository.obtenerArbolesUser(correo);
      _arbolesUsuarioFetcher.sink.add(ApiResponse.completed(arbol));
    } on Exception {
      _arbolesUsuarioFetcher.sink.add(ApiResponse.error());
    }
  }

  Stream<ApiResponse<ArbolModel>> get arbolesUser =>
      _arbolesUsuarioFetcher.stream;

  Stream<ApiResponse<ArbolModel>> get arboles =>
      _todosArbolesFetcher.stream;
}
