package com.example.db

import com.typesafe.scalalogging.LazyLogging
import com.zaxxer.hikari.{HikariConfig, HikariDataSource}

import java.sql.Connection
import scala.util.Using

case class Portfolio(id: Int, name: String, userId: String, balance: Double)

class PortfolioRepository(dataSource: HikariDataSource) extends LazyLogging:

  def init(): Unit =
    Using(dataSource.getConnection()) { conn =>
      conn.createStatement().execute(
        """CREATE TABLE IF NOT EXISTS portfolios (
          |  id      SERIAL PRIMARY KEY,
          |  name    VARCHAR(255) NOT NULL,
          |  user_id VARCHAR(255) NOT NULL,
          |  balance DECIMAL(15,2) DEFAULT 0.0
          |)""".stripMargin
      )
      logger.info("Portfolios table ready")
    }.get

  // JDBC calls here are auto-instrumented by the OTel Java agent — no manual
  // span creation needed. The agent adds db.system, db.statement attributes.
  def findAll(): List[Portfolio] =
    Using(dataSource.getConnection()) { conn =>
      val rs = conn.createStatement().executeQuery("SELECT id, name, user_id, balance FROM portfolios")
      val buf = scala.collection.mutable.ListBuffer.empty[Portfolio]
      while rs.next() do
        buf += Portfolio(rs.getInt("id"), rs.getString("name"), rs.getString("user_id"), rs.getDouble("balance"))
      buf.toList
    }.getOrElse(Nil)

  def findById(id: Int): Option[Portfolio] =
    Using(dataSource.getConnection()) { conn =>
      val stmt = conn.prepareStatement("SELECT id, name, user_id, balance FROM portfolios WHERE id = ?")
      stmt.setInt(1, id)
      val rs = stmt.executeQuery()
      if rs.next() then
        Some(Portfolio(rs.getInt("id"), rs.getString("name"), rs.getString("user_id"), rs.getDouble("balance")))
      else None
    }.getOrElse(None)

  def create(name: String, userId: String, balance: Double): Portfolio =
    Using(dataSource.getConnection()) { conn =>
      val stmt = conn.prepareStatement(
        "INSERT INTO portfolios (name, user_id, balance) VALUES (?, ?, ?) RETURNING id"
      )
      stmt.setString(1, name)
      stmt.setString(2, userId)
      stmt.setDouble(3, balance)
      val rs = stmt.executeQuery()
      rs.next()
      Portfolio(rs.getInt("id"), name, userId, balance)
    }.get

object PortfolioRepository:
  def apply(url: String, user: String, password: String): PortfolioRepository =
    val config = HikariConfig()
    config.setJdbcUrl(url)
    config.setUsername(user)
    config.setPassword(password)
    config.setMaximumPoolSize(10)
    config.setConnectionTestQuery("SELECT 1")
    new PortfolioRepository(HikariDataSource(config))
